param(
  [Parameter(Mandatory=$true)][string]$Root,
  [string]$IntelDir = (Join-Path $Root "archive\\intel"),
  [string]$OutDir   = (Join-Path $Root "content\\intel"),
  [string]$Title    = "Podilsk.InfoHub — Daily Brief"
)
$ErrorActionPreference="Stop"

function Html([string]$s){
  if($null -eq $s){ return "" }
  $s = $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
  return $s
}

$rawPath = Join-Path $IntelDir "raw-latest.jsonl"
$becPath = Join-Path $IntelDir "beacons-latest.json"
$day = (Get-Date).ToString("yyyy-MM-dd")

$raw = @()
if(Test-Path $rawPath){
  Get-Content $rawPath | % { if($_){ try{ $raw += ($_ | ConvertFrom-Json) } catch{} } }
}
$beacons = @()
if(Test-Path $becPath){
  try{ $beacons = Get-Content -Raw $becPath | ConvertFrom-Json } catch { $beacons=@() }
}
if($beacons -and -not ($beacons -is [System.Collections.IEnumerable])){ $beacons=@($beacons) }

$beacons = $beacons | %{
  $b=$_
  $examples=@()
  if($b.PSObject.Properties.Name -contains 'TopExamples'){
    $v=$b.TopExamples
    if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])){ $examples=@($v) } else { $examples=@($v) }
  }
  [pscustomobject]@{ Id=$b.Id; Severity=$b.Severity; Count=$b.Count; SinceUtc=$b.SinceUtc; WindowH=$b.WindowH; TopExamples=$examples }
}

$null = New-Item -ItemType Directory -Force -Path $OutDir
$htmlDay = Join-Path $OutDir ("{0}.html" -f $day)
$htmlLatest = Join-Path $OutDir "latest.html"

$head = @"
<!DOCTYPE html><html lang="uk"><head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>$Title ($day)</title>
<style>
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Arial,sans-serif;margin:24px;line-height:1.5}
h1{font-size:22px;margin:0 0 12px}
h2{font-size:18px;margin:20px 0 8px}
.card{border:1px solid #e5e7eb;border-radius:12px;padding:12px 16px;margin:8px 0;background:#fff}
.badge{display:inline-block;border-radius:999px;padding:2px 8px;font-size:12px;border:1px solid #e5e7eb;margin-left:6px}
.badge.high{background:#fee2e2}
.badge.medium{background:#fef3c7}
ul{margin:8px 0 0 18px}
.meta{color:#6b7280;font-size:12px}
a{color:#1d4ed8;text-decoration:none}
a:hover{text-decoration:underline}
</style>
</head><body>
<h1>$Title ($day)</h1>`n<div style="margin:8px 0 16px">" + (Test-Path (Join-Path $Root "media-kit\\logo.svg") `
? "<img alt=""logo"" src=""../../media-kit/logo.svg"" style=""height:40px"">" : "") + "</div>"
"@

$secBeacons = "<h2>Маяки</h2>"
if($beacons.Count -gt 0){
  foreach($b in $beacons){
    $sev = ("" + $b.Severity).ToLower()
    $secBeacons += "<div class=""card""><div><strong>" + (Html $b.Id) + "</strong><span class=""badge $sev"">" + (Html $b.Severity) + "</span></div>"
    $secBeacons += "<div class=""meta"">count: $($b.Count) • since: " + (Html $b.SinceUtc) + "</div>"
    if($b.TopExamples -and $b.TopExamples.Count -gt 0){
      $secBeacons += "<ul>"
      foreach($ex in ($b.TopExamples | Select-Object -First 5)){
        $t = Html $ex.Title
        $u = Html $ex.Url
        $s = Html $ex.Score
        $secBeacons += "<li><a href=""$u"">$t</a> <span class=""meta"">(score: $s)</span></li>"
      }
      $secBeacons += "</ul>"
    }
    $secBeacons += "</div>"
  }
} else {
  $secBeacons += "<div class=""card""><em>Маяків у вікні не виявлено.</em></div>"
}

$secRaw = "<h2>Події (raw, топ 10)</h2>"
if($raw.Count -gt 0){
  $top = $raw | Sort-Object Score -Descending | Select-Object -First 10
  foreach($it in $top){
    $t = Html $it.Title; $u = Html $it.Url
    $pub = Html $it.Published
    $topics = if($it.Topics){ Html (($it.Topics -join ", ")) } else { "-" }
    $places = if($it.Places){ Html (($it.Places -join ", ")) } else { "-" }
    $s = Html $it.Score
    $secRaw += "<div class=""card""><a href=""$u""><strong>$t</strong></a><div class=""meta"">$pub • topics: $topics • places: $places • score: $s</div></div>"
  }
} else {
  $secRaw += "<div class=""card""><em>Подій не зібрано.</em></div>"
}

$foot = "</body></html>"

# write
$doc = $head + $secBeacons + $secRaw + $foot
$enc = New-Object System.Text.UTF8Encoding($true)
[IO.File]::WriteAllText($htmlDay,   $doc, $enc)
Copy-Item -LiteralPath $htmlDay -Destination $htmlLatest -Force

Write-Host "[ OK ] HTML brief:" -ForegroundColor Green
Write-Host "  $htmlDay"
Write-Host "  $htmlLatest"