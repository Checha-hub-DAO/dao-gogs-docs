<#
  RADAR-SourceTrust_Apply.ps1
  Підтягує довіру джерел (SourceTrust) у artifacts.csv з довідника DICT\SourceTrust.csv

  Пріоритет відповідності: source > author > domain > regex
  Режими поєднання з наявним Trust/SourceTrust:
    - Overwrite (за замовчуванням): замінити значення
    - Max: взяти максимум зі старого й нового
    - Average: середнє (арифметичне)

  Створює .bak і лог RADAR_SOURCETRUST_LOG.md
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = "D:\CHECHA_CORE",
  [string]$CsvPath,                           # artifacts.csv
  [string]$DictPath,                          # DICT\SourceTrust.csv
  [ValidateSet('Overwrite','Max','Average')]
  [string]$Mode = 'Overwrite',
  [double]$DefaultTrust = 0.2,                # якщо не знайдено відповідності
  [switch]$AlsoWriteToTrust,                  # крім SourceTrust, записати в колонку Trust
  [switch]$DryRun
)

function Log([string]$m,[string]$lvl="INFO"){ $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; Write-Host "[$lvl] $ts $m" }
function Ensure-Dir([string]$p){ if($p -and !(Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function TryNum([string]$s){ if([string]::IsNullOrWhiteSpace($s)){ return $null } $s2=$s -replace ',','.'; $n=0.0; if([double]::TryParse($s2,[ref]$n)){ $n } else { $null } }

# --- домен із URL
function Extract-Domain([string]$src){
  if([string]::IsNullOrWhiteSpace($src)){ return $null }
  try{
    if($src -match '^(https?://)'){
      $u = [Uri]$src
      $host = $u.Host
      if($host.StartsWith("www.")){ $host = $host.Substring(4) }
      return $host
    }
    return $null
  } catch { return $null }
}

# --- застосувати режим поєднання
function Merge-Trust($old, $new, [string]$mode){
  if($null -eq $old){ return $new }
  switch($mode){
    'Overwrite' { return $new }
    'Max'       { return [Math]::Max([double]$old,[double]$new) }
    'Average'   { return ([double]$old + [double]$new) / 2.0 }
  }
}

try{
  # 0) Шляхи
  if([string]::IsNullOrWhiteSpace($CsvPath)){  $CsvPath  = Join-Path $RepoRoot 'RADAR\INDEX\artifacts.csv' }
  if([string]::IsNullOrWhiteSpace($DictPath)){ $DictPath = Join-Path $RepoRoot 'RADAR\DICT\SourceTrust.csv' }
  if(!(Test-Path -LiteralPath $CsvPath)){  throw "Не знайдено індекс: $CsvPath" }
  if(!(Test-Path -LiteralPath $DictPath)){ throw "Не знайдено довідник: $DictPath" }

  # 1) Завантаження
  $rows = Import-Csv -LiteralPath $CsvPath
  if(-not $rows -or $rows.Count -eq 0){ throw "Порожній artifacts.csv" }
  $dict = Import-Csv -LiteralPath $DictPath | Where-Object {
    $_.key_type -and $_.key_value -and $_.trust -ne $null
  }

  # 2) Індексація довідника
  $mapSource = @{}; $mapAuthor = @{}; $mapDomain = @{}
  $regexList = New-Object System.Collections.Generic.List[object]
  foreach($d in $dict){
    $t = [double](TryNum $d.trust); if($null -eq $t){ continue }
    $k = $d.key_value
    switch($d.key_type.ToLower()){
      'source' { $mapSource[$k] = $t }
      'author' { $mapAuthor[$k] = $t }
      'domain' { $mapDomain[$k] = $t }
      'regex'  {
        try{ $regexList.Add([pscustomobject]@{ rx = [regex]$k; trust = $t }) } catch {}
      }
    }
  }

  Log ("Довідник: source={0}, author={1}, domain={2}, regex={3}" -f $mapSource.Count,$mapAuthor.Count,$mapDomain.Count,$regexList.Count)

  # 3) Обробка індексу
  $total = $rows.Count; $updated = 0; $matched = 0; $byType = [ordered]@{source=0;author=0;domain=0;regex=0;default=0}

  $out = foreach($r in $rows){
    $src   = $r.source
    $auth  = $r.author
    $dom   = Extract-Domain $src
    $oldST = TryNum $r.SourceTrust
    if($null -eq $oldST){ $oldST = TryNum $r.Trust }

    $newST = $null
    $reason= $null

    if($src -and $mapSource.ContainsKey($src)){ $newST = $mapSource[$src]; $reason='source'; $byType.source++ }
    elseif($auth -and $mapAuthor.ContainsKey($auth)){ $newST = $mapAuthor[$auth]; $reason='author'; $byType.author++ }
    elseif($dom -and $mapDomain.ContainsKey($dom)){ $newST = $mapDomain[$dom]; $reason='domain'; $byType.domain++ }
    else{
      $rxHit = $null
      foreach($rx in $regexList){
        if($src -and $rx.rx.IsMatch($src)){ $rxHit = $rx; break }
      }
      if($rxHit){ $newST = $rxHit.trust; $reason='regex'; $byType.regex++ }
      else{ $newST = $DefaultTrust; $reason='default'; $byType.default++ }
    }

    $final = if($oldST -ne $null){ Merge-Trust $oldST $newST $Mode } else { $newST }
    if(($oldST -eq $null -and $final -ne $null) -or ([Math]::Abs($final - $oldST) -gt 1e-9)){ $updated++ }
    if($reason -ne 'default'){ $matched++ }

    $r | Add-Member -NotePropertyName SourceTrust -NotePropertyValue ([Math]::Round([double]$final, 6)) -Force
    if($AlsoWriteToTrust){ $r | Add-Member -NotePropertyName Trust -NotePropertyValue ([Math]::Round([double]$final,6)) -Force }
    $r | Add-Member -NotePropertyName SourceTrust_Reason -NotePropertyValue $reason -Force
    $r
  }

  Log ("Рядків: {0}; оновлено: {1}; знайдено відповідностей (не default): {2}" -f $total,$updated,$matched)
  Log ("Breakdown → source={0}, author={1}, domain={2}, regex={3}, default={4}" -f $byType.source,$byType.author,$byType.domain,$byType.regex,$byType.default)

  if($DryRun){
    Log "DryRun: CSV не перезаписано"
    exit 0
  }

  # 4) Запис результату
  $bak = "$CsvPath.bak"
  Copy-Item -LiteralPath $CsvPath -Destination $bak -Force
  $hdr = $rows[0].PSObject.Properties.Name
  foreach($need in @('SourceTrust','SourceTrust_Reason')){
    if($hdr -notcontains $need){ $hdr += $need }
  }
  if($AlsoWriteToTrust -and $hdr -notcontains 'Trust'){ $hdr += 'Trust' }

  $tmp  = [System.IO.Path]::GetTempFileName()
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  $sb   = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine(($hdr -join ','))
  foreach($r in $out){
    $vals = foreach($h in $hdr){
      $v = $r.$h
      if($null -eq $v){ "" }
      else{
        $s=[string]$v
        if($s -match '[,"\r\n]'){ '"' + ($s -replace '"','""') + '"' } else { $s }
      }
    }
    [void]$sb.AppendLine(($vals -join ','))
  }
  [System.IO.File]::WriteAllText($tmp,$sb.ToString(),$utf8)
  Move-Item -LiteralPath $tmp -Destination $CsvPath -Force

  # 5) Лог
  $logDir = Join-Path $RepoRoot 'C03_LOG'; Ensure-Dir $logDir
  Add-Content -Path (Join-Path $logDir 'RADAR_SOURCETRUST_LOG.md') -Encoding UTF8 `
    ("- [{0}] File='{1}' | Updated={2}/{3} | Mode={4} | DefaultTrust={5} | Breakdown: {6}" -f `
      (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $CsvPath, $updated, $total, $Mode, $DefaultTrust,
      ("source={0}, author={1}, domain={2}, regex={3}, default={4}" -f $byType.source,$byType.author,$byType.domain,$byType.regex,$byType.default))

  Log "Готово."
  exit 0
}
catch{
  Log $_.Exception.Message "ERR"
  exit 2
}
