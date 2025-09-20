param([Parameter(Mandatory)][string]$Root)
$ErrorActionPreference = "Stop"
$root   = (Resolve-Path -LiteralPath $Root).Path
$today  = Get-Date
$rawDir = Join-Path $root ("data\raw\" + $today.ToString("yyyy-MM-dd"))
$normDir= Join-Path $root "data\normalized"
$incDir = Join-Path $root "data\incidents"
New-Item -ItemType Directory -Force -Path $normDir,$incDir | Out-Null
$rules  = Get-Content -Raw -LiteralPath (Join-Path $root "agents\analyzer\config\rules.json")  | ConvertFrom-Json
$beacon = Get-Content -Raw -LiteralPath (Join-Path $root "agents\analyzer\config\beacons.json")| ConvertFrom-Json
$normalized = @()
Get-ChildItem -LiteralPath $rawDir -Filter "rss_*.xml" -ErrorAction SilentlyContinue | ForEach-Object {
  try{
    [xml]$x = Get-Content -LiteralPath $_.FullName
    $items = @()
    if($x.rss.channel.item){ $items = $x.rss.channel.item }
    elseif($x.feed.entry){ $items = $x.feed.entry }
    foreach($i in $items | Select-Object -First 999){
      $title = ($i.title | Out-String).Trim()
      $link  = ($i.link.href,$i.link,$i.enclosure.url | Where-Object {$_})[0]
      $desc  = ($i.description,"",$i.summary | Where-Object {$_})[0] -replace '\s+',' '
      $pub   = ($i.pubDate,$i.updated,$i.published | Where-Object {$_})[0]
      $ts    = try{ [datetime]$pub } catch { $today }
      $normalized += [pscustomobject]@{
        id=[guid]::NewGuid().ToString("N"); source=$_.BaseName; title=$title
        text="$title. $desc"; link=$link; pubdate=$ts.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
      }
    }
  } catch { Write-Host "[WARN] parse fail: $($_.Name)" -ForegroundColor Yellow }
}
$incidents = @()
foreach($n in $normalized){
  $t = ($n.title + " " + $n.text).ToLower()
  $score = 0; $hits=@()
  foreach($r in $rules){
    $hit=$false
    foreach($kw in $r.match_any){ if($t -like ("*" + $kw.ToLower() + "*")){ $hit=$true; break } }
    if($hit){ $score += [int]$r.score; $hits += $r.id }
  }
  if($hits.Count -gt 0){
    $incidents += [pscustomobject]@{
      id=$n.id; pubdate=$n.pubdate; source=$n.source; title=$n.title; link=$n.link; score=$score; rules=($hits -join ",")
    }
  }
}
$dayNorm = Join-Path $normDir ("items_" + $today.ToString("yyyy-MM-dd") + ".jsonl")
$normalized | ForEach-Object { ($_ | ConvertTo-Json -Compress) } | Set-Content -LiteralPath $dayNorm -Encoding UTF8
$dayInc = Join-Path $incDir ("incidents_" + $today.ToString("yyyy-MM-dd") + ".csv")
"Id,PubDate,Source,Title,Link,Score,Rules" | Set-Content -LiteralPath $dayInc -Encoding UTF8
$incidents | ForEach-Object {
  $line = '"{0}",{1},{2},"{3}",{4},{5},"{6}"' -f $_.id,$_.pubdate,$_.source.Replace('"','""'),$_.title.Replace('"','""'),$_.link,$_.score,$_.rules
  Add-Content -LiteralPath $dayInc -Value $line
}
$beaconsOut = @()
foreach($m in $beacon.metrics){
  $count = ($incidents | Where-Object {
    $r = $_.rules -split ","; ($m.ruleIds | Where-Object { $r -contains $_ }).Count -gt 0
  }).Count
  $beaconsOut += [pscustomobject]@{ id=$m.id; name=$m.name; count=$count; date=$today.ToString("yyyy-MM-dd") }
}
$dayB = Join-Path $normDir ("beacons_" + $today.ToString("yyyy-MM-dd") + ".csv")
"Id,Name,Date,Count" | Set-Content -LiteralPath $dayB -Encoding UTF8
$beaconsOut | ForEach-Object { '{0},"{1}",{2},{3}' -f $_.id,$_.name.Replace('"','""'),$_.date,$_.count } | Add-Content -LiteralPath $dayB
Write-Host "[ OK ] normalized: $($normalized.Count) | incidents: $($incidents.Count) | beacons: $($beaconsOut.Count)" -ForegroundColor Green
