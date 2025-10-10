<# 
.SYNOPSIS
  Будує/оновлює каталог технічних інструментів:
  - сканує .ps1/.psm1 у вказаних коренях
  - перевіряє синтаксис (Parser)
  - рахує SHA256
  - формує/оновлює C11_TOOLS_INDEX\TOOLS_MAP.csv
  - генерує C11_TOOLS_INDEX\TOOLS_INDEX.md (оглядова таблиця)

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\CHECHA_CORE\TOOLS\Generate-ToolsIndex.ps1"
#>

[CmdletBinding()]
param(
  [string[]] $RootPaths = @(
    'D:\CHECHA_CORE\TOOLS',
    'D:\CHECHA_CORE\INBOX',
    'D:\CHECHA_CORE\C12_KNOWLEDGE\MD_AUDIT'
  ),
  [string] $OutDir = 'D:\CHECHA_CORE\C11_TOOLS_INDEX',
  [switch] $PreserveNotes  # якщо задано — зберігає існуючі "note" та "status" із CSV
)

# --- Підготовка виводу ---
$null = New-Item -ItemType Directory -Force -Path $OutDir
$csvPath = Join-Path $OutDir 'TOOLS_MAP.csv'
$mdPath  = Join-Path $OutDir 'TOOLS_INDEX.md'

# --- Хелпери ---
function Test-ParseOk {
  param([string]$Path)
  try {
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
      $Path, [ref]([string[]]@()), [ref]([System.Management.Automation.Language.ParseError[]]@())
    )
    # Якщо будуть помилки, виключення не кинеться — їх треба зчитати з другого параметра.
    # Тому зробимо ще один прохід з отриманням помилок:
    $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]([string[]]@()), [ref]$errs) | Out-Null
    if ($errs -and $errs.Count -gt 0) { return @{ Ok = $false; Error = ($errs[0].Message) } }
    return @{ Ok = $true; Error = $null }
  } catch {
    return @{ Ok = $false; Error = $_.Exception.Message }
  }
}

function Get-GitContext {
  param([string]$Dir)
  try {
    Push-Location $Dir
    $inside = (git rev-parse --is-inside-work-tree 2>$null)
    if ($inside -eq 'true') {
      $origin = (git config --get remote.origin.url 2>$null)
      return @{ Inside = $true; Origin = $origin }
    }
    return @{ Inside = $false; Origin = $null }
  } catch {
    return @{ Inside = $false; Origin = $null }
  } finally { Pop-Location }
}

function Get-StatusFromSignals {
  param(
    [hashtable]$ParseInfo,
    [string]$Path
  )
  if (-not $ParseInfo.Ok) { return 'ERROR' }
  # додаткові легкі евристики
  if ($Path -match 'New-OrUpdate-CheChaTask') { return 'WARN' }
  if ($Path -match 'Run-NewLoveWeekBlock')   { return 'WARN' }
  return 'OK'
}

# --- Завантажити існуючий CSV (для PreserveNotes) ---
$existing = @{}
if (Test-Path $csvPath) {
  try {
    (Import-Csv -Path $csvPath) | ForEach-Object {
      $existing[$_.path] = $_
    }
  } catch {}
}

# --- Збір файлів ---
$files = @()
foreach ($root in $RootPaths) {
  if (Test-Path $root) {
    $files += Get-ChildItem $root -Recurse -File -Include *.ps1, *.psm1 -ErrorAction SilentlyContinue
  }
}

# --- Побудова записів ---
$rows = New-Object System.Collections.Generic.List[Object]
$counter = 0

foreach ($f in $files) {
  $counter++
  $code = 'A' + "{0:D3}" -f $counter
  $parse = Test-ParseOk -Path $f.FullName
  $hash  = (Get-FileHash -Algorithm SHA256 -Path $f.FullName).Hash
  $git   = Get-GitContext -Dir $f.DirectoryName
  $status = Get-StatusFromSignals -ParseInfo $parse -Path $f.FullName
  $note = ''

  if ($PreserveNotes -and $existing.ContainsKey($f.FullName)) {
    if ($existing[$f.FullName].note)   { $note = $existing[$f.FullName].note }
    if ($existing[$f.FullName].status) { $status = $existing[$f.FullName].status }
  } else {
    if (-not $parse.Ok -and $parse.Error) { $note = "Parser: $($parse.Error)" }
    elseif ($git.Inside -and -not $git.Origin) { $note = "Git: missing origin" }
  }

  $rows.Add([pscustomobject]@{
    code           = $code
    name           = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    type           = 'PowerShell'
    path           = $f.FullName
    status         = $status
    last_seen_utc  = (Get-Date).ToUniversalTime().ToString("s") + 'Z'
    sha256         = $hash
    note           = $note
  }) | Out-Null
}

# --- Злиття з ручним “стартовим” CSV (додати несценовані об’єкти) ---
# Якщо у стартовому CSV були нефайлові елементи (напр., .xlsx інструменти) — збережемо їх.
if (Test-Path $csvPath) {
  try {
    $prior = Import-Csv -Path $csvPath
    foreach ($p in $prior) {
      if (-not $p.path -or -not (Test-Path $p.path)) {
        # додати, якщо нема дублікату по 'code'/'name'
        if (-not ($rows | Where-Object { $_.code -eq $p.code -or $_.name -eq $p.name })) {
          $rows.Add($p) | Out-Null
        }
      }
    }
  } catch {}
}

# --- Запис CSV ---
$rows | Sort-Object name | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

# --- Генерація Markdown-огляду ---
$md = @()
$md += "# 📖 Каталог технічних інструментів (авто-індекс)"
$md += ""
$md += "> Оновлено: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
$md += ""
$md += "| Код | Назва | Тип | Статус | Примітка |"
$md += "|-----|-------|-----|--------|----------|"

foreach ($r in ($rows | Sort-Object name)) {
  $n = $r.name -replace '\|','\|'
  $t = $r.type
  $s = $r.status
  $noteCell = ($r.note -replace '\|','\|')
  $md += "| $($r.code) | $n | $t | $s | $noteCell |"
}

$md -join "`r`n" | Set-Content -Path $mdPath -Encoding UTF8

Write-Host "[OK] CSV: $csvPath"
Write-Host "[OK] MD : $mdPath"
