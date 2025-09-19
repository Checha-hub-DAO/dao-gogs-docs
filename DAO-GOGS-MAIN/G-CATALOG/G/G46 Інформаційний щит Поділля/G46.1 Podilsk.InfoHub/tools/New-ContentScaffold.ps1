param(
  [Parameter(Mandatory)][string]$Root
)
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path -LiteralPath $Root).Path
$content = Join-Path $Root "content"
New-Item -ItemType Directory -Force -Path $content | Out-Null

$files = @(
  @{Name="01-welcome.md";                 Title="# Podilsk.InfoHub — purpose";       Body="Mission, principles, how to join."; },
  @{Name="02-how-to-help.md";             Title="# How to help";                      Body="Steps for volunteers/partners."; },
  @{Name="03-press-release-template.md";  Title="# Press release template";           Body="Date, headline, lead, quotes, contacts."; },
  @{Name="04-crisis-response-procedure.md";Title="# Crisis response plan (TOC)";      Body="Collect facts -> verify -> notify -> press."; },
  @{Name="05-media-guidelines.md";        Title="# Media guidelines (fact-check)";    Body="How to verify sources; right to comment."; }
)

foreach($f in $files){
  $p = Join-Path $content $f.Name
  if(-not (Test-Path -LiteralPath $p)){
    @"
$($f.Title)

$f.Body

"@ | Set-Content -LiteralPath $p -Encoding UTF8
  }
}

Write-Host "[ OK ] Content scaffold: $content" -ForegroundColor Green
