<# 
.SYNOPSIS
  Зведення/оновлення бази контактів для G46 зі стандартною схемою + дедуплікація.

.EXAMPLE
  .\Export-ContactsCsv.ps1 -Root "D:\CHECHA_CORE\G46-Podilsk.InfoHub" -InputCsv @("locals.csv","media.csv")

.PARAMETER Root
  Корінь модуля (де папка /contacts).

.PARAMETER InputCsv
  Список локальних CSV, які треба злити у єдину базу.

.PARAMETER UrlCsv
  Список URL (CSV), які треба підтягнути (наприклад, експорт Google Sheets як CSV).

.PARAMETER OutFile
  Вихідний файл. За замовчуванням: <Root>\contacts\podillia_contacts.csv

.NOTES
  Схема колонок:
  Name, Org, Role, City, Phone, Email, Channel, Notes, Source, Verified, UpdatedUtc
#>
param(
  [Parameter(Mandatory)][string]$Root,
  [string[]]$InputCsv,
  [string[]]$UrlCsv,
  [string]$OutFile
)

$ErrorActionPreference = "Stop"
function Info($m){ Write-Host "ℹ️  $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "✅ $m" -ForegroundColor Green }
function Warn($m){ Write-Host "⚠️  $m" -ForegroundColor Yellow }

$Root = (Resolve-Path $Root).Path
$contactsDir = Join-Path $Root "contacts"
New-Item -ItemType Directory -Force -Path $contactsDir | Out-Null
$OutFile = if($OutFile){ $OutFile } else { Join-Path $contactsDir "podillia_contacts.csv" }

$cols = "Name","Org","Role","City","Phone","Email","Channel","Notes","Source","Verified","UpdatedUtc"
$bag  = New-Object System.Collections.Generic.List[object]

function Normalize-Row($r){
  $obj = [ordered]@{}
  foreach($c in $cols){ $obj[$c] = $null }

  $obj["Name"]   = ($r.Name, $r.FullName, $r.Contact, $r["Ім'я"]) -ne $null | Select-Object -First 1
  $obj["Org"]    = ($r.Org, $r.Organization, $r.Company, $r["Організація"]) -ne $null | Select-Object -First 1
  $obj["Role"]   = ($r.Role, $r.Position, $r["Посада"]) -ne $null | Select-Object -First 1
  $obj["City"]   = ($r.City, $r.Location, $r["Місто"]) -ne $null | Select-Object -First 1
  $obj["Phone"]  = ($r.Phone, $r.Tel, $r["Телефон"]) -ne $null | Select-Object -First 1
  $obj["Email"]  = ($r.Email, $r.Mail, $r["Ел.пошта"]) -ne $null | Select-Object -First 1
  $obj["Channel"]= ($r.Channel, $r.Platform, $r["Канал"]) -ne $null | Select-Object -First 1
  $obj["Notes"]  = ($r.Notes, $r.Note, $r["Нотатки"]) -ne $null | Select-Object -First 1
  $obj["Source"] = ($r.Source, $r.Origin, $r["Джерело"]) -ne $null | Select-Object -First 1
  $obj["Verified"]   = ($r.Verified, $r["Перевірено"]) -ne $null | Select-Object -First 1
  $obj["UpdatedUtc"] = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

  # Прості нормалізації
  if($obj["Email"]){ $obj["Email"] = $obj["Email"].ToString().Trim().ToLower() }
  if($obj["Phone"]){ $obj["Phone"] = ($obj["Phone"] -replace '[^\d\+]','').Trim() }

  return [PSCustomObject]$obj
}

# 1) Pull URL CSVs (за потреби)
$tmp = New-Item -ItemType Directory -Force -Path (Join-Path $contactsDir "_tmp") | Select-Object -ExpandProperty FullName
if($UrlCsv){
  foreach($u in $UrlCsv){
    try{
      Info "Завантажую: $u"
      $fn = Join-Path $tmp ("url_" + [System.Guid]::NewGuid().ToString("N") + ".csv")
      Invoke-WebRequest -Uri $u -OutFile $fn -UseBasicParsing
      $InputCsv += $fn
    } catch {
      Warn "Не вдалося завантажити $u: $($_.Exception.Message)"
    }
  }
}

# 2) Merge + normalize
foreach($f in $InputCsv){
  if(-not (Test-Path $f)){ Warn "Пропускаю, немає файлу: $f"; continue }
  Info "Імпортую: $f"
  $rows = Import-Csv $f
  foreach($r in $rows){ $bag.Add( (Normalize-Row $r) ) }
}

# 3) Dedup (Email|Phone)
$dedup = $bag | Group-Object { 
  $key = ""
  if($_.Email){ $key += "E:" + $_.Email }
  if($_.Phone){ $key += "|P:" + $_.Phone }
  if([string]::IsNullOrWhiteSpace($key)){ $key = "NO_KEY:" + [guid]::NewGuid().ToString("N") }
  $key
} | ForEach-Object {
  # Залишаємо перший елемент у групі
  $_.Group | Select-Object -First 1
}

# 4) Ensure header & export
if(Test-Path $OutFile){ Remove-Item $OutFile -Force }
$dedup | Select-Object $cols | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutFile

# 5) Cleanup
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

Ok "Готово: $OutFile (записів: $($dedup.Count))"
