<#
  RADAR-Fingerprint.ps1
  Заповнює sha256 у RADAR\INDEX\artifacts.csv
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = "D:\CHECHA_CORE",
  [string]$CsvPath,
  [switch]$ForceRecalc,        # перерахувати навіть якщо sha256 вже є
  [switch]$DryRun
)

function Write-Log([string]$m,[string]$lvl="INFO"){
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; Write-Host "[$lvl] $ts $m"
}
function Sha256OfBytes([byte[]]$bytes){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try   { ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join '' }
  finally { $sha.Dispose() }
}
function Sha256OfFile([string]$path){
  if(!(Test-Path -LiteralPath $path)){ return $null }
  $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
  try{
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { ($sha.ComputeHash($fs) | ForEach-Object { $_.ToString("x2") }) -join '' }
    finally { $sha.Dispose() }
  } finally { $fs.Dispose() }
}
function Sha256OfString([string]$s){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $bytes = $enc.GetBytes($s); Sha256OfBytes $bytes
}

try{
  if([string]::IsNullOrWhiteSpace($CsvPath)){ $CsvPath = Join-Path $RepoRoot 'RADAR\INDEX\artifacts.csv' }
  if(!(Test-Path -LiteralPath $CsvPath)){ throw "Не знайдено індекс: $CsvPath" }

  $rows = Import-Csv -LiteralPath $CsvPath
  if(-not $rows -or $rows.Count -eq 0){ throw "Порожній CSV: $CsvPath" }

  $changed = 0
  $total   = $rows.Count

  $out = foreach($r in $rows){
    $need = $ForceRecalc -or [string]::IsNullOrWhiteSpace($r.sha256)
    $sha = $r.sha256
    $src = $r.SHA_Source

    if($need){
      $fp = $r.filepath
      $calc = $null
      $src  = $null
      if($fp -and (Test-Path -LiteralPath $fp)){
        $calc = Sha256OfFile $fp
        $src  = 'file'
      } else {
        $x = '{0}|{1}|{2}|{3}|{4}' -f $r.id,$r.title,$r.summary,$r.source,$r.timestamp
        $calc = Sha256OfString $x
        $src  = 'content'
      }
      if($calc){
        if($sha -ne $calc){ $changed++ }
        $sha = $calc
      }
    }

    $r | Add-Member -NotePropertyName sha256     -NotePropertyValue $sha -Force
    $r | Add-Member -NotePropertyName SHA_Source -NotePropertyValue $src -Force
    $r
  }

  if($DryRun){
    Write-Log "DryRun: змінено б записів: $changed / $total"
    exit 0
  }

  $bak = "$CsvPath.bak"
  Copy-Item -LiteralPath $CsvPath -Destination $bak -Force
  $header = $rows[0].PSObject.Properties.Name
  if($header -notcontains 'sha256'){     $header += 'sha256' }
  if($header -notcontains 'SHA_Source'){ $header += 'SHA_Source' }

  $tmp = [System.IO.Path]::GetTempFileName()
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine(($header -join ','))
  foreach($r in $out){
    $vals = foreach($h in $header){
      $v = $r.$h
      if($null -eq $v){ "" }
      else {
        $s = [string]$v
        if($s -match '[,"\r\n]'){ '"' + ($s -replace '"','""') + '"' } else { $s }
      }
    }
    [void]$sb.AppendLine(($vals -join ','))
  }
  [System.IO.File]::WriteAllText($tmp,$sb.ToString(),$utf8)
  Move-Item -LiteralPath $tmp -Destination $CsvPath -Force

  $logDir = Join-Path $RepoRoot 'C03_LOG'; if(!(Test-Path $logDir)){ New-Item -ItemType Directory -Path $logDir | Out-Null }
  Add-Content -Path (Join-Path $logDir 'RADAR_FINGERPRINT_LOG.md') -Encoding UTF8 `
    ("- [{0}] File='{1}' | Rows={2} | Changed={3} | Force={4}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $CsvPath, $total, $changed, $ForceRecalc)

  Write-Log "Готово: змінено $changed / $total"
  exit 0
}
catch{
  Write-Log $_.Exception.Message "ERR"; exit 2
}
