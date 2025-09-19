<# 
.SYNOPSIS
  Генерує стартові контент-файли для G46 (/content).

.EXAMPLE
  .\New-ContentScaffold.ps1 -Root "D:\CHECHA_CORE\G46-Podilsk.InfoHub"
#>
param(
  [Parameter(Mandatory)][string]$Root
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path $Root).Path
$content = Join-Path $Root "content"
New-Item -ItemType Directory -Force -Path $content | Out-Null

$files = @(
  @{Name="01-welcome.md"; Title="# Інформаційний щит Поділля — навіщо і як працює"; Body="Коротко про місію, принципи, як долучитись."},
  @{Name="02-how-to-help.md"; Title="# Як долучитись та допомогти"; Body="Покрокові інструкції для волонтерів/партнерів."},
  @{Name="03-press-release-template.md"; Title="# Шаблон прес-релізу"; Body="Дата, заголовок, лід, цитати, контакти."},
  @{Name="04-crisis-response-procedure.md"; Title="# План кризового реагування (TOC)"; Body="Огляд етапів: збір фактів → верифікація → повідомлення → преса."},
  @{Name="05-media-guidelines.md"; Title="# Гайд для журналістів: факти та перевірка"; Body="Як перевіряти джерела, контакти, право на коментар."}
)

foreach($f in $files){
  $p = Join-Path $content $f.Name
  if(-not (Test-Path $p)){
    "# $($f.Title)`n`n$fBody" -replace '\$fBody',$f.Body | Out-File -FilePath $p -Encoding UTF8
  }
}

Write-Host "✅ Content scaffold OK: $content" -ForegroundColor Green
