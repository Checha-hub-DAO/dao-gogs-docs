[CmdletBinding()]
Param(
  [string]$Root = "D:\CHECHA_CORE",
  [switch]$All,
  [string[]]$Modules,
  [switch]$Quiet
)
Set-StrictMode -Version Latest; $ErrorActionPreference='Stop'

$logDir = Join-Path $Root 'C03\LOG'; New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logPath = Join-Path $logDir 'releases_validate.log'
function W([string]$s,[string]$lvl='INFO'){ $l="$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$lvl] $s"; Add-Content $logPath $l; if(-not $Quiet){Write-Host $l} }

$targets=@()
if($All){
  $targets = @(Get-ChildItem -Path (Join-Path $Root 'C11') -Directory |
               Where-Object { Test-Path (Join-Path $_.FullName 'Release') })
}elseif($Modules){
  foreach($m in $Modules){ $p=Join-Path (Join-Path $Root 'C11') $m; if (Test-Path (Join-Path $p 'Release')){$targets += (Get-Item $p)} }
}else{
  $p = Join-Path (Join-Path $Root 'C11') 'SHIELD4_ODESA'
  if (Test-Path (Join-Path $p 'Release')){$targets += (Get-Item $p)}
}

$fail=0
foreach($t in $targets){
  $rel = Join-Path $t.FullName 'Release'
  $chk = Join-Path (Split-Path $rel -Parent) 'Archive\CHECKSUMS.txt'
  W "Module: $($t.Name) | ReleaseDir: $rel"

  $sum=@{}
  if(Test-Path $chk){
    Get-Content $chk | ForEach-Object {
      if($_ -match '^\s*([0-9A-Fa-f]{64})\s+\*(.+)$'){ $sum[$Matches[2]]=$Matches[1] }
    }
  } else { W "No CHECKSUMS.txt: $chk" 'WARN' }

  $zips = Get-ChildItem $rel -Filter *.zip -File -ErrorAction SilentlyContinue
  foreach($z in $zips){
    $ok=$true; $name=$z.Name
    if($sum.ContainsKey($name)){
      try{
        $h = Get-FileHash $z.FullName -Algorithm SHA256
        if($h.Hash.ToLower() -ne $sum[$name].ToLower()){ W "SHA256 mismatch: $name" 'WARN'; $ok=$false }
      }catch{ W "Hash error: $name" 'WARN'; $ok=$false }
    } else { W "No entry in CHECKSUMS for: $name" 'WARN' }
    if($ok){ W "OK: $name" } else { $fail++ }
  }
}
if($fail -gt 0){ if(-not $Quiet){Write-Host "Fails: $fail" -ForegroundColor Red}; exit 2 }
else{ if(-not $Quiet){Write-Host "All good" -ForegroundColor Green}; exit 0 }
