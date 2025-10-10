# D:\CHECHA_CORE\TOOLS\Update-MANIFEST-Metrics.ps1
[CmdletBinding()]
param(
  [string]$ManifestPath = "D:\CHECHA_CORE\MANIFEST.md",
  [string]$ScoreCsv     = "D:\CHECHA_CORE\C07_ANALYTICS\C12_IntegrityScore.csv",
  [string]$C13LatestMd  = "D:\CHECHA_CORE\C13_LEARNING_FEEDBACK\LATEST.md",
  [int]$ScoreHistory    = 3,
  [int]$C13Lines        = 6,
  [string]$LogPath      = "D:\CHECHA_CORE\C03_LOG\control\Update-MANIFEST-Metrics.log"
)

function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Log([string]$m){ $l="[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$m; $l; try{$l|Tee-Object -File $LogPath -Append|Out-Null}catch{} }

Ensure-Dir (Split-Path -Parent $ManifestPath)
Ensure-Dir (Split-Path -Parent $LogPath)

Log "START Update-MANIFEST-Metrics"
Log "Manifest=$ManifestPath"

# ---------- 1) Зчитати IntegrityScore ----------
$scoreLine = '- IntegrityScore: n/a'
$scoreTable = @()
if (Test-Path -LiteralPath $ScoreCsv) {
  try {
    $rows = Import-Csv -LiteralPath $ScoreCsv | ForEach-Object {
      # Обережний parse дати
      $dt = $_.Date
      try { $dt = [datetime]::Parse($_.Date) } catch {}
      [pscustomobject]@{
        Date = $dt
        WeeksChecked = $_.WeeksChecked
        Ok = $_.Ok
        Score = if($_.Score){ [int]$_.Score } else { $_.IntegrityScore }
        SourceCsv = $_.SourceCsv
      }
    } | Sort-Object Date -Descending

    if ($rows -and $rows.Count -gt 0) {
      $last = $rows | Select-Object -First 1
      $scoreVal = $last.Score
      $when = if($last.Date){ $last.Date.ToString('yyyy-MM-dd HH:mm:ss') } else { $last.Date }
      $scoreLine = ("- IntegrityScore: **{0}** (at {1})" -f $scoreVal, $when)

      # Табличка історії (останні N)
      $history = $rows | Select-Object -First $ScoreHistory
      $scoreTable += '| Date | Score | Weeks | OK |'
      $scoreTable += '|---|---:|---:|:--:|'
      foreach($r in $history){
        $d = if($r.Date){ $r.Date.ToString('yyyy-MM-dd HH:mm') } else { $r.Date }
        $ok = if($r.Ok -match '^(True|true)$'){ '✓' } else { '—' }
        $w  = $r.WeeksChecked
        $s  = $r.Score
        $scoreTable += ("| {0} | {1} | {2} | {3} |" -f $d,$s,$w,$ok)
      }
    }
  } catch { Log "[WARN] Score parse: $($_.Exception.Message)" }
} else {
  Log "[INFO] Score CSV not found: $ScoreCsv"
}

# ---------- 2) Зчитати C13 (LATEST.md) ----------
$c13Block = @('- C13: n/a')
if (Test-Path -LiteralPath $C13LatestMd) {
  try {
    $raw = Get-Content -LiteralPath $C13LatestMd -ErrorAction Stop
    # беремо ключову секцію Summary + перші рядки Weeks
    $summaryIdx = ($raw | Select-String -Pattern '^\s*##\s*Summary' -SimpleMatch).LineNumber
    if($summaryIdx){
      $slice = $raw[($summaryIdx-1) .. ([math]::Min($raw.Length-1, $summaryIdx-1 + $C13Lines))]
      # Залишимо лише марковані пункти/корисні рядки
      $filtered = $slice | Where-Object { $_ -match '^\s*- ' -or $_ -match '^\s*##\s*Summary' }
      if($filtered){ $c13Block = $filtered }
    } else {
      # fallback: просто перші N маркованих рядків
      $bullets = $raw | Where-Object { $_ -match '^\s*- ' } | Select-Object -First $C13Lines
      if($bullets){ $c13Block = $bullets }
    }
  } catch { Log "[WARN] C13 read: $($_.Exception.Message)" }
} else {
  Log "[INFO] C13 LATEST not found: $C13LatestMd"
}

# ---------- 3) Зібрати секцію METRICS ----------
$block = @()
$block += "<!-- BEGIN METRICS -->"
$block += "## Metrics"
$block += $scoreLine
if($scoreTable){ $block += ""; $block += "### IntegrityScore (history)"; $block += $scoreTable }
$block += ""
$block += "### C13 — Learning Feedback"
$block += $c13Block
$block += "<!-- END METRICS -->"
$blockText = ($block -join "`r`n")

# ---------- 4) Запис у MANIFEST.md ----------
if(-not (Test-Path -LiteralPath $ManifestPath)){
  "# MANIFEST`r`n`r`n$blockText`r`n" | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  Log "[NEW] Created MANIFEST with Metrics."
} else {
  $content = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
  $regex = New-Object System.Text.RegularExpressions.Regex('<!-- BEGIN METRICS -->.*?<!-- END METRICS -->',[System.Text.RegularExpressions.RegexOptions]::Singleline)
  if($regex.IsMatch($content)){
    $m=$regex.Match($content)
    $updated = $content.Substring(0,$m.Index) + $blockText + $content.Substring($m.Index+$m.Length)
    Log "[OK] Metrics section updated (replace)."
  } else {
    $updated = $content.TrimEnd() + "`r`n`r`n" + $blockText + "`r`n"
    Log "[OK] Metrics section appended."
  }
  Set-Content -LiteralPath $ManifestPath -Value $updated -Encoding UTF8
}

Log "END Update-MANIFEST-Metrics"
