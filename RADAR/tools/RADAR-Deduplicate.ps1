<#
  RADAR-Deduplicate.ps1
  Знаходить і маркує дублі в artifacts.csv (soft-mode).
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = "D:\CHECHA_CORE",
  [string]$CsvPath,
  [switch]$DryRun
)

function Write-Log([string]$m,[string]$lvl="INFO"){
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; Write-Host "[$lvl] $ts $m"
}
function NormTitle([string]$s){
  if([string]::IsNullOrWhiteSpace($s)){ return "" }
  $s = $s.ToLower().Trim()
  $s = ($s -replace '\s+',' ')
  return $s
}
function DayOnly($ts){
  $d=$null
  if([datetime]::TryParse([string]$ts,[ref]$d)){ return $d.Date.ToString('yyyy-MM-dd') }
  return ""
}

try{
  if([string]::IsNullOrWhiteSpace($CsvPath)){ $CsvPath = Join-Path $RepoRoot 'RADAR\INDEX\artifacts.csv' }
  if(!(Test-Path -LiteralPath $CsvPath)){ throw "Не знайдено індекс: $CsvPath" }

  $rows = Import-Csv -LiteralPath $CsvPath
  if(-not $rows -or $rows.Count -eq 0){ throw "Порожній CSV" }

  # Підготовка полів
  foreach($r in $rows){
    $r | Add-Member -NotePropertyName IsDuplicate -NotePropertyValue $false -Force
    $r | Add-Member -NotePropertyName DuplicateOf -NotePropertyValue "" -Force
  }

  $dupes = New-Object System.Collections.Generic.List[object]

  # 1) Дублі за sha256
  $bySha = $rows | Where-Object { $_.sha256 } | Group-Object sha256 | Where-Object { $_.Count -gt 1 }
  foreach($g in $bySha){
    $group = $g.Group
    # еталон — найстарший (за timestamp) або перший
    $ref = $group | Sort-Object { [datetime]$_.timestamp } | Select-Object -First 1
    foreach($x in $group){
      if($x -ne $ref){
        $x.IsDuplicate = $true
        $x.DuplicateOf = $ref.sha256
        $dupes.Add([pscustomobject]@{
          Reason      = 'sha256'
          DuplicateId = $x.id
          ReferenceId = $ref.id
          Sha256      = $g.Name
          TitleDup    = $x.title
          TitleRef    = $ref.title
          TsDup       = $x.timestamp
          TsRef       = $ref.timestamp
        })
      }
    }
  }

  # 2) Сурогатні дублі: однаковий нормалізований title + той самий день
  $rows | ForEach-Object {
    $_ | Add-Member -NotePropertyName _title_norm -NotePropertyValue (NormTitle $_.title) -Force
    $_ | Add-Member -NotePropertyName _day        -NotePropertyValue (DayOnly   $_.timestamp) -Force
  } | Out-Null

  $byKey = $rows | Group-Object { "{0}|{1}" -f $_._title_norm, $_._day } | Where-Object { $_.Count -gt 1 -and $_.Name -ne "|" }
  foreach($g in $byKey){
    $group = $g.Group | Sort-Object { [datetime]$_.timestamp }
    $ref = $group | Select-Object -First 1
    foreach($x in $group | Select-Object -Skip 1){
      if(-not $x.IsDuplicate){
        $x.IsDuplicate = $true
        $x.DuplicateOf = ($ref.sha256 ? $ref.sha256 : $ref.id)
        $dupes.Add([pscustomobject]@{
          Reason      = 'title+day'
          DuplicateId = $x.id
          ReferenceId = $ref.id
          Sha256      = $ref.sha256
          TitleDup    = $x.title
          TitleRef    = $ref.title
          TsDup       = $x.timestamp
          TsRef       = $ref.timestamp
        })
      }
    }
  }

  $dupCount = $dupes.Count
  Write-Log "Знайдено дублікатів: $dupCount"

  # Файл дублікатів
  $idxDir = Split-Path -Parent $CsvPath
  $stamp  = (Get-Date).ToString('yyyyMMdd_HHmmss')
  $dupsCsv= Join-Path $idxDir ("duplicates_{0}.csv" -f $stamp)

  if($DryRun){
    if($dupCount -gt 0){ $dupes | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $dupsCsv }
    Write-Log "DryRun: маркування у головний CSV не виконано. Звіт: $dupsCsv"
    exit 0
  }

  # Запис дублікатів та оновленого індексу
  if($dupCount -gt 0){ $dupes | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $dupsCsv }

  $bak = "$CsvPath.bak"; Copy-Item -LiteralPath $CsvPath -Destination $bak -Force
  $hdr = $rows[0].PSObject.Properties.Name
  if($hdr -notcontains 'IsDuplicate'){ $hdr += 'IsDuplicate' }
  if($hdr -notcontains 'DuplicateOf'){ $hdr += 'DuplicateOf' }
  if($hdr -contains '_title_norm'){ $hdr = $hdr | Where-Object { $_ -ne '_title_norm' } }
  if($hdr -contains '_day'){ $hdr = $hdr | Where-Object { $_ -ne '_day' } }

  $tmp = [System.IO.Path]::GetTempFileName()
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine(($hdr -join ','))
  foreach($r in $rows){
    $vals = foreach($h in $hdr){
      $v=$r.$h
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

  $logDir = Join-Path $RepoRoot 'C03_LOG'; if(!(Test-Path $logDir)){ New-Item -ItemType Directory -Path $logDir | Out-Null }
  Add-Content -Path (Join-Path $logDir 'RADAR_DEDUP_LOG.md') -Encoding UTF8 `
    ("- [{0}] File='{1}' | Duplicates={2} | Report='{3}'" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $CsvPath, $dupCount, ($dupCount -gt 0 ? $dupsCsv : "<none>"))

  Write-Log "Готово: позначено дублікатів $dupCount; звіт: $dupsCsv"
  exit 0
}
catch{
  Write-Log $_.Exception.Message "ERR"; exit 2
}
