<#
.SYNOPSIS
Повний цикл релізу META: символи → пакет → підпис → перевірка → журнал → release-notes → git.

.VERSION
v1.2 — 2025-11-12

.ADDITIONS
- Автогенерація ReleaseNotes_<STAMP>.md (UTF-8)
- Перевірка git-репо і акуратне додавання реліз-нот у коміт
- Легка ініціалізація UTF-8 для виводу (щоб GPG не кракозябрив ім’я)
#>

[CmdletBinding()]
param(
  [string]$Root  = "D:\CHECHA_CORE",
  [string]$KeyId = "D0944CAC3E8EA390",
  [switch]$SkipVerify,
  [switch]$NoGitPush,
  [string]$Stamp
)

$ErrorActionPreference = 'Stop'
function _ok($m){ Write-Host "[OK]  $m" -ForegroundColor Green }
function _info($m){ Write-Host "[INFO] $m" }
function _warn($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function _err($m){ Write-Host "[ERR] $m" -ForegroundColor Red }

# --- UTF-8 console (щоб gpg і кирилиця виглядали нормально) ---
try { chcp 65001 > $null } catch {}
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$env:LANG = "C.UTF-8"; $env:LC_ALL = "C.UTF-8"

try {
  $tools   = Join-Path $Root "TOOLS"
  $focus   = Join-Path $Root "C06_FOCUS"
  $reports = Join-Path $Root "C03_LOG\reports\META"
  if(-not (Test-Path $reports)){ New-Item -ItemType Directory -Path $reports -Force | Out-Null }

  Write-Host "🚀 META-RELEASE v1.2" -ForegroundColor Cyan

  # 1) Генерація PNG
  $gen = Join-Path $tools "Generate-META-SymbolsPng.ps1"
  if(Test-Path $gen){ _info "Генерую символи…"; & $gen } else { _warn "Не знайдено $gen — пропускаю PNG" }

  # 2) Пакування + підпис (через Build-META-Package v1.1.0+)
  $pack = Join-Path $tools "Build-META-Package.ps1"
  if(-not (Test-Path $pack)){ throw "Не знайдено $pack" }

  $packParams = @{
    Root  = $Root
    Quiet = $true
  }
  $cmd = Get-Command -Name $pack -ErrorAction Stop
  if ($cmd.Parameters.ContainsKey('Sign'))  { $packParams['Sign']  = $true; $packParams['KeyId'] = $KeyId }
  if ($Stamp)                               { $packParams['Stamp'] = $Stamp }

  _info "Пакую та підписую…"
  & $pack @packParams

  # 3) Останній ZIP і споріднені файли
  $zip = Get-ChildItem -Path $focus -Filter "META_Revival_*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if(-not $zip){ throw "ZIP не знайдено у $focus" }
  $zipPath = $zip.FullName
  $ascPath = "$zipPath.asc"
  $jsonPath = Join-Path $focus (($zip.Name) -replace '\.zip$','_MANIFEST.json')
  if(-not (Test-Path $jsonPath)){ throw "MANIFEST.json не знайдено: $jsonPath" }
  _ok ("ZIP → {0}" -f $zip.Name)

  # 4) Перевірка підпису
  if(-not $SkipVerify){
    _info "Перевіряю GPG-підпис…"
    & gpg --verify "$ascPath" "$zipPath" | Out-Null
    _ok "Підпис валідний (gpg --verify)"
  } else { _warn "SkipVerify: пропущено перевірку підпису" }

  # 5) Звірка SHA
  _info "Звіряю SHA256 (MANIFEST.json vs ZIP)…"
  $manifest = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
  $sha_manifest = "$($manifest.sha256)".Trim().ToUpperInvariant()
  $sha_real     = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
  if($sha_manifest -ne $sha_real){ _err "SHA mismatch: MANIFEST=$sha_manifest, REAL=$sha_real"; throw "MANIFEST_SHA_MISMATCH" }
  _ok "SHA OK: $sha_real"

  # 6) Експорт публічного ключа
  $pubkey = Join-Path $focus "checha_pubkey.asc"
  & gpg --armor --export $KeyId > $pubkey
  _ok "Публічний ключ оновлено → checha_pubkey.asc"

  # 7) Журнал запусків релізу
  $runsCsv = Join-Path $reports "META_ReleaseRuns.csv"
  if(-not (Test-Path $runsCsv)){
    "Timestamp,ZipName,ZipSize,SHA256,Verified,KeyId,Stamp,Note" | Set-Content -LiteralPath $runsCsv -Encoding UTF8
  }
  $verified = $(if($SkipVerify){"skipped"}else{"gpg-ok"})
  $note = "auto-release v1.2"
  $size = (Get-Item -LiteralPath $zipPath).Length
  ('"{0}","{1}",{2},"{3}","{4}","{5}","{6}","{7}"' -f `
    (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), (Split-Path -Leaf $zipPath), $size, $sha_real, $verified, $KeyId, ($Stamp ?? ""), $note) |
    Add-Content -LiteralPath $runsCsv -Encoding UTF8
  _ok "Журнал запусків оновлено → META_ReleaseRuns.csv"

  # 8) Release Notes (UTF-8) — створюємо в C06_FOCUS
  # STAMP для файла нотаток: якщо не заданий, беремо з назви ZIP
  if(-not $Stamp){
    if($zip.BaseName -match '_(\d{4}-\d{2}-\d{2})$'){ $Stamp = $Matches[1] } else { $Stamp = (Get-Date -Format 'yyyy-MM-dd') }
  }
  $notesPath = Join-Path $focus ("ReleaseNotes_{0}.md" -f $Stamp)

  $notes = @"
## META-Revival 1.1 — $Stamp
- S1–S8 PNG згенеровано
- Оновлено: META_Revival_1.1.md, META_SYMBOLS.csv
- ZIP: $(Split-Path -Leaf $zipPath)
- SHA256: $sha_real
- Підпис: $(Split-Path -Leaf $ascPath)
- Публічний ключ: $(Split-Path -Leaf $pubkey)

### Перевірка
gpg --import $(Split-Path -Leaf $pubkey)
gpg --verify $(Split-Path -Leaf $ascPath) $(Split-Path -Leaf $zipPath)
(Get-FileHash $(Split-Path -Leaf $zipPath) -Algorithm SHA256).Hash.ToUpper()
"@
  $notes | Set-Content -LiteralPath $notesPath -Encoding UTF8
  _ok ("Release Notes створено → {0}" -f (Split-Path -Leaf $notesPath))

  # 9) Git: переконатися, що ми в репо
  Set-Location $Root
  if((git rev-parse --is-inside-work-tree 2>$null) -ne 'true'){
    _warn "Не git-репозиторій: $Root — крок git буде пропущено"
    Write-Host "`n✅ META-RELEASE v1.2 завершено (без git)." -ForegroundColor Green
    exit 0
  }

  # 10) Git add/commit/tag/push
  $gitFiles = @(
    "C06_FOCUS\META_Revival_1.1_*.zip*",
    "C06_FOCUS\checha_pubkey.asc",
    "C06_FOCUS\META_Revival_1.1_*.json",
    "C06_FOCUS\ReleaseNotes_*.md",
    "C03_LOG\reports\META\META_Packages.csv",
    "C03_LOG\reports\META\META_ReleaseRuns.csv"
  )
  git add $gitFiles -f

  $msg = "META-Revival release $(Get-Date -Format yyyy-MM-dd_HH-mm) | sha=$sha_real"
  git commit -m $msg | Out-Null

  $tagName = "META-Revival-$(Get-Date -Format yyyy-MM-dd_HH-mm)"
  git tag -s $tagName -m "CheCha CORE / DAO-GOGS META package (signed)"
  _ok "Git: commit + signed tag → $tagName"

  if(-not $NoGitPush){
    git push
    git push --tags
    _ok "Git: push + tags"
  } else { _warn "NoGitPush: пуш пропущено" }

  Write-Host "`n✅ META-RELEASE v1.2 завершено успішно." -ForegroundColor Green
  exit 0
}
catch {
  _err $_
  if($_ -is [System.Management.Automation.ErrorRecord]){
    if($_.FullyQualifiedErrorId){ _err ("FQID: " + $_.FullyQualifiedErrorId) }
    if($_.ScriptStackTrace){ _warn $_.ScriptStackTrace }
  }
  exit 1
}
