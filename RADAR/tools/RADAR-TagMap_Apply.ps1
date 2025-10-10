<#
  RADAR-TagMap_Apply.ps1
  На основі TagMap_GModules.csv проставляє GModule/GModules у artifacts.csv.
  Опційно встановлює Relevance за ModuleRelevance.csv.

  Як працює:
    1) Читає tags з індексу (роздільники , ; |).
    2) Нормалізує (нижній регістр, trim).
    3) Для кожного тегу шукає співпадіння у довіднику:
         - key_type=tag → точний збіг
         - key_type=regex → збіг за RegEx до всього тегу
    4) Формує кандидатів {module → найвищий confidence / priority}.
    5) Визначає головний модуль (GModule) за режимом:
         - HighestPriority (за замовчуванням)
         - Score (max confidence)
         - FirstMatch (перший знайдений)
    6) Пише:
         - GModule           — головний модуль
         - GModules          — список "MODULE(confidence|prio)" через ; 
         - GModule_SourceTag — який тег(и) дали головний модуль
         - (опц.) Relevance  — з ModuleRelevance або дефолт
    7) Лог у C03_LOG\RADAR_TAGMAP_LOG.md, .bak копія CSV.
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = "D:\CHECHA_CORE",
  [string]$CsvPath,                                 # artifacts.csv
  [string]$TagMapPath,                              # DICT\TagMap_GModules.csv
  [ValidateSet('HighestPriority','Score','FirstMatch')]
  [string]$Mode = 'HighestPriority',
  [string]$ModuleRelevancePath,                     # DICT\ModuleRelevance.csv (необов'язково)
  [double]$DefaultRelevance = 0.7,                  # якщо немає мапи або модуля в ній
  [switch]$WriteRelevance,                          # записати колонку Relevance
  [switch]$DryRun
)

function Log([string]$m,[string]$lvl="INFO"){ $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; Write-Host "[$lvl] $ts $m" }
function Ensure-Dir([string]$p){ if($p -and !(Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function SplitTags([string]$s){
  if([string]::IsNullOrWhiteSpace($s)){ return @() }
  return ($s -split '[,;|]+' | ForEach-Object { ($_ -as [string]).Trim().ToLower() } | Where-Object { $_ -ne '' })
}
function TryNum([string]$s){ if([string]::IsNullOrWhiteSpace($s)){ return $null } $s2=$s -replace ',','.'; $n=0.0; if([double]::TryParse($s2,[ref]$n)){ $n } else { $null } }

try{
  # Шляхи
  if([string]::IsNullOrWhiteSpace($CsvPath)){     $CsvPath     = Join-Path $RepoRoot 'RADAR\INDEX\artifacts.csv' }
  if([string]::IsNullOrWhiteSpace($TagMapPath)){  $TagMapPath  = Join-Path $RepoRoot 'RADAR\DICT\TagMap_GModules.csv' }
  if(!(Test-Path -LiteralPath $CsvPath)){  throw "Не знайдено індекс: $CsvPath" }
  if(!(Test-Path -LiteralPath $TagMapPath)){ throw "Не знайдено довідник: $TagMapPath" }

  # Дані
  $rows   = Import-Csv -LiteralPath $CsvPath
  if(-not $rows -or $rows.Count -eq 0){ throw "Порожній artifacts.csv" }

  $mapRaw = Import-Csv -LiteralPath $TagMapPath | Where-Object { $_.key_type -and $_.key_value -and $_.module }
  if(-not $mapRaw -or $mapRaw.Count -eq 0){ throw "Порожній TagMap_GModules.csv" }

  # Підготовити regex-и
  $rules = foreach($m in $mapRaw){
    $kt = ($m.key_type ?? '').ToLower()
    $kv = [string]$m.key_value
    $mod= [string]$m.module
    $prio = [int]([int]::TryParse($m.priority, [ref]([ref]0).Value); if($m.priority -match '^\d+$'){ [int]$m.priority } else { 0 })
    $conf = TryNum $m.confidence; if($null -eq $conf){ $conf = 1.0 }

    if($kt -eq 'regex'){
      $rx = $null
      try{ $rx = [regex]$kv } catch { continue }
      [pscustomobject]@{ type='regex'; key=$rx; module=$mod; priority=$prio; confidence=$conf; src=$kv }
    }
    elseif($kt -eq 'tag'){
      [pscustomobject]@{ type='tag'; key=$kv.ToLower(); module=$mod; priority=$prio; confidence=$conf; src=$kv }
    }
  }

  # Мапа релевантності модулів (опційно)
  $moduleRel = @{}
  if($WriteRelevance -and $ModuleRelevancePath){
    if(Test-Path -LiteralPath $ModuleRelevancePath){
      foreach($r in (Import-Csv -LiteralPath $ModuleRelevancePath)){
        if($r.module){
          $moduleRel[$r.module] = [double](TryNum $r.relevance)
          if($moduleRel[$r.module] -eq $null){ $moduleRel[$r.module] = $DefaultRelevance }
        }
      }
    }
  }

  # Основний цикл
  $total=$rows.Count; $updated=0; $matchedRows=0
  $mode = $Mode

  $out = foreach($r in $rows){
    $tags = SplitTags $r.tags
    $cands = @{}   # module → @{priority=..; confidence=..; tags=Set[string]}
    $hitTags = @{} # module → set of matching tags (for primary trace)

    foreach($t in $tags){
      foreach($rule in $rules){
        $isHit = $false
        if($rule.type -eq 'tag'){ if($t -eq $rule.key){ $isHit = $true } }
        else { if($rule.key.IsMatch($t)){ $isHit = $true } }

        if($isHit){
          if(-not $cands.ContainsKey($rule.module)){
            $cands[$rule.module] = [ordered]@{ priority = $rule.priority; confidence = $rule.confidence }
            $hitTags[$rule.module] = New-Object 'System.Collections.Generic.HashSet[string]'
          } else {
            # акумулюємо найвищі значення
            if($rule.priority  -gt $cands[$rule.module].priority ){ $cands[$rule.module].priority  = $rule.priority }
            if($rule.confidence -gt $cands[$rule.module].confidence){ $cands[$rule.module].confidence = $rule.confidence }
          }
          [void]$hitTags[$rule.module].Add($t)
        }
      }
    }

    $gmod = ""; $gmodsList = ""; $srcTags = ""

    if($cands.Count -gt 0){
      $matchedRows++

      # список для GModules: MODULE(conf|prio)
      $gmodsList = ($cands.GetEnumerator() | ForEach-Object {
        "{0}({1}|{2})" -f $_.Key, ([Math]::Round([double]$_.Value.confidence,3)), $_.Value.priority
      }) -join '; '

      # вибір головного модуля
      switch($mode){
        'FirstMatch' {
          # умовно візьмемо по найвищій priority; якщо однакові — перший
          $gmod = ($cands.GetEnumerator() | Sort-Object { - $_.Value.priority } | Select-Object -First 1).Key
        }
        'Score' {
          $gmod = ($cands.GetEnumerator() | Sort-Object { - $_.Value.confidence } | Select-Object -First 1).Key
        }
        default { # HighestPriority
          $gmod = ($cands.GetEnumerator() | Sort-Object { - $_.Value.priority }, { - $_.Value.confidence } | Select-Object -First 1).Key
        }
      }

      if($gmod -and $hitTags.ContainsKey($gmod)){
        $srcTags = ($hitTags[$gmod].GetEnumerator() | Sort-Object | ForEach-Object { $_ }) -join ', '
      }
    }

    # Чи оновлено
    $before = @($r.GModule, $r.GModules, $r.GModule_SourceTag) -join '||'
    $r | Add-Member -NotePropertyName GModule            -NotePropertyValue $gmod      -Force
    $r | Add-Member -NotePropertyName GModules           -NotePropertyValue $gmodsList -Force
    $r | Add-Member -NotePropertyName GModule_SourceTag  -NotePropertyValue $srcTags   -Force

    # Relevance (опційно)
    if($WriteRelevance){
      $rel = $null
      if($gmod -and $moduleRel.ContainsKey($gmod)){ $rel = $moduleRel[$gmod] }
      elseif($gmod){ $rel = $DefaultRelevance }
      if($rel -ne $null){
        $r | Add-Member -NotePropertyName Relevance -NotePropertyValue ([Math]::Round([double]$rel,6)) -Force
      }
    }

    $after = @($r.GModule, $r.GModules, $r.GModule_SourceTag) -join '||'
    if($before -ne $after){ $updated++ }
    $r
  }

  Log ("Рядків: {0}; з мапінгом: {1}; оновлено: {2}" -f $total,$matchedRows,$updated)

  if($DryRun){
    Log "DryRun: CSV не перезаписано"
    exit 0
  }

  # Запис
  $bak = "$CsvPath.bak"; Copy-Item -LiteralPath $CsvPath -Destination $bak -Force
  $hdr = $rows[0].PSObject.Properties.Name
  foreach($need in @('GModule','GModules','GModule_SourceTag')){
    if($hdr -notcontains $need){ $hdr += $need }
  }
  if($WriteRelevance -and $hdr -notcontains 'Relevance'){ $hdr += 'Relevance' }

  $tmp  = [System.IO.Path]::GetTempFileName()
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  $sb   = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine(($hdr -join ','))
  foreach($r in $out){
    $vals = foreach($h in $hdr){
      $v=$r.$h
      if($null -eq $v){ "" } else {
        $s=[string]$v
        if($s -match '[,"\r\n]'){ '"' + ($s -replace '"','""') + '"' } else { $s }
      }
    }
    [void]$sb.AppendLine(($vals -join ','))
  }
  [System.IO.File]::WriteAllText($tmp,$sb.ToString(),$utf8)
  Move-Item -LiteralPath $tmp -Destination $CsvPath -Force

  # Лог
  $logDir = Join-Path $RepoRoot 'C03_LOG'; Ensure-Dir $logDir
  Add-Content -Path (Join-Path $logDir 'RADAR_TAGMAP_LOG.md') -Encoding UTF8 `
    ("- [{0}] File='{1}' | Mode={2} | MatchedRows={3}/{4} | Updated={5} | TagMap='{6}' | ModuleRel='{7}'" -f `
      (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $CsvPath, $Mode, $matchedRows, $total, $updated, $TagMapPath, ($ModuleRelevancePath ?? "<none>"))

  Log "Готово."
  exit 0
}
catch{
  Log $_.Exception.Message "ERR"
  exit 2
}
