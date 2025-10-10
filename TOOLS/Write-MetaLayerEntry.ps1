# Write-MetaLayerEntry.ps1 — ФІНАЛЬНА СТАБІЛЬНА ВЕРСІЯ
# Призначення: додає YAML-блок у кінець META_LAYER_LOG.md
# Сумісність: PowerShell 5.1 / 7.x

param(
  [string]$RepoRoot = "D:\CHECHA_CORE",
  [string]$LogPath  = "",
  [Parameter(Mandatory=$true)][string]$Event,
  [string]$Intent,
  [string]$Observation,
  [string]$Insight,
  [string]$EmotionalTone,
  [double]$BalanceShift = 0.0,
  [double]$MetaIndex = -1,
  [string[]]$Tags = @(),
  [datetime]$Now = (Get-Date)
)

# -------- helpers --------

function Ensure-Dir([string]$p){
  $d = Split-Path -Parent $p
  if($d -and -not (Test-Path -LiteralPath $d)){
    New-Item -ItemType Directory -Path $d -Force | Out-Null
  }
}

function Ensure-FileWithBom([string]$p){
  if(-not (Test-Path -LiteralPath $p)){
    Ensure-Dir $p
    [byte[]]$bom = 0xEF,0xBB,0xBF
    [System.IO.File]::WriteAllBytes($p, $bom)
  } else {
    try {
      [byte[]]$first3 = [System.IO.File]::ReadAllBytes($p)[0..2]
    } catch { $first3 = @() }
    if($first3.Count -lt 3 -or $first3[0] -ne 0xEF -or $first3[1] -ne 0xBB -or $first3[2] -ne 0xBF){
      $bytes = [System.IO.File]::ReadAllBytes($p)
      [byte[]]$bom = 0xEF,0xBB,0xBF
      [System.IO.File]::WriteAllBytes($p, $bom + $bytes)
    }
  }
}

function Escape-Yaml([string]$s){
  if([string]::IsNullOrEmpty($s)){ return "" }
  $s = $s -replace "`r`n","`n" -replace "`r","`n"
  if($s -match "`n"){
    $prefixed = @()
    foreach($ln in ($s -split "`n")){ $prefixed += ("  " + $ln) }
    return "|`r`n" + ([string]::Join("`r`n",$prefixed))
  } else {
    $q = $s -replace '"','\"'
    return '"' + $q + '"'
  }
}

# -------- resolve target path --------

if(-not $LogPath){
  $LogPath = Join-Path $RepoRoot 'C12_KNOWLEDGE\MD_SYSTEM\META_LAYER_LOG.md'
}
Ensure-FileWithBom $LogPath

# -------- time & numbers --------

$iso = $Now.ToString('yyyy-MM-dd HH:mm')

if($BalanceShift -lt -1){ $BalanceShift = -1 }
elseif($BalanceShift -gt 1){ $BalanceShift = 1 }

if($MetaIndex -lt 0){
  $tmp = 0.6 + 0.2 * [math]::Max(0,$BalanceShift)
} else {
  $tmp = [double]$MetaIndex
}
if($tmp -lt 0){ $tmp = 0 } elseif($tmp -gt 1){ $tmp = 1 }
$MetaIndex = [math]::Round($tmp,2)

# -------- ensure header --------

$needHeader = $true
try {
  $fi = Get-Item -LiteralPath $LogPath -ErrorAction Stop
  if($fi.Length -gt 0){ $needHeader = $false }
} catch {}

if($needHeader){
  $headerLines = @(
    '# 📜 META_LAYER_LOG',
    '**CheCha System | Версія формату:** v1.0  ',
    '**Дата створення:** ' + (Get-Date).ToString('yyyy-MM-dd') + '  ',
    '**Автор:** С.Ч.  ',
    '**Призначення:** Журнал мета-усвідомлення — записи після дій/скриптів.',
    ''
  )
  $headerText = [string]::Join("`r`n",$headerLines)
  [System.IO.File]::AppendAllText($LogPath,$headerText,[System.Text.Encoding]::UTF8)
}

# -------- build YAML block --------

$lines = @()
$lines += ('- Date: ' + $iso)
$lines += ('  Event: ' + (Escape-Yaml $Event))
if($Intent){        $lines += ('  Intent: ' + (Escape-Yaml $Intent)) }
if($Observation){   $lines += ('  Observation: ' + (Escape-Yaml $Observation)) }
if($Insight){       $lines += ('  Insight: ' + (Escape-Yaml $Insight)) }
if($EmotionalTone){ $lines += ('  EmotionalTone: ' + (Escape-Yaml $EmotionalTone)) }
$lines += ('  BalanceShift: ' + ("{0:N2}" -f $BalanceShift))
$lines += ('  MetaIndex: ' + ("{0:N2}" -f $MetaIndex))
if($Tags -and $Tags.Count -gt 0){
  $t = @()
  foreach($x in $Tags){ if($x){ $t += ($x.Trim().Replace('[','(').Replace(']',')')) } }
  if($t.Count -gt 0){ $lines += ('  Tag: [' + ([string]::Join(', ',$t)) + ']') }
}

$blockLines = @('```yaml') + $lines + @('```','')
$blockText  = [string]::Join("`r`n",$blockLines)

[System.IO.File]::AppendAllText($LogPath,$blockText,[System.Text.Encoding]::UTF8)

exit 0
