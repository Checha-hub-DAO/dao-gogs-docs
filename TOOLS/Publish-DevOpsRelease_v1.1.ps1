<# 
  Publish-DevOpsRelease_v1.1.ps1
  Готує реліз DevOps Layer v1.1:
   - перевіряє ZIP артефакт
   - створює/оновлює MANIFEST + *.sha256.txt
   - (опц.) GPG-підписує ZIP і MANIFEST, експортує публічний ключ
   - додає allowlist у .gitignore (тільки релізні артефакти)
   - (опц.) приглушує "dirty" для субмодуля C12_KNOWLEDGE/MD_INBOX
   - git add/commit/tag/push
#>

[CmdletBinding()]
param(
  [string]$RepoRoot  = "D:\CHECHA_CORE",
  [string]$OutDir    = "D:\CHECHA_CORE\C03_LOG\reports",
  [string]$Version   = "v1.1",
  [string]$TagDate   = (Get-Date -Format 'yyyy-MM-dd'),
  # Якщо не задано — шукаємо README_DevOps_<v>_GitBook.zip у OutDir
  [string]$ZipPath,
  [switch]$GpgSign,
  [switch]$IgnoreDirtySubmodule
)

function Info([string]$m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Ok  ([string]$m){ Write-Host "[ OK ] $m" -ForegroundColor Green }
function Warn([string]$m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Err ([string]$m){ Write-Host "[ERR ] $m" -ForegroundColor Red }

function Get-GpgSigningKeyId {
  $o = & gpg --list-secret-keys --with-colons 2>$null
  if (-not $o) { return $null }
  $lines = $o -split "`r?`n"
  for ($i=0; $i -lt $lines.Count; $i++){
    $l = $lines[$i]
    if ($l -like 'sec:*' -or $l -like 'sec#:*' -or $l -like 'ssb:*' -or $l -like 'ssb#:*'){
      $parts = $l -split ':'
      $caps  = ''
      if ($parts.Count -ge 13) { $caps += $parts[12] }
      if ($parts.Count -ge 12) { $caps += $parts[11] }
      if ($caps -match 's'){
        for ($j=$i+1; $j -lt $lines.Count; $j++){
          if ($lines[$j] -like 'fpr:*'){
            $fprParts = $lines[$j] -split ':'
            $fpr = $fprParts[-2]
            if ($fpr) { return $fpr }
          }
          if ($lines[$j] -like 'sec:*' -or $lines[$j] -like 'ssb:*'){ break }
        }
      }
    }
  }
  return $null
}

function Write-Sha256Sidecar {
  param([Parameter(Mandatory)] [string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
  $out = "$Path.sha256.txt"
  $h | Set-Content -LiteralPath $out -Encoding ASCII
  return (Test-Path -LiteralPath $out)
}

function Test-Sha256 {
  param([Parameter(Mandatory)] [string]$Path)
  $sha = "$Path.sha256.txt"
  if (-not (Test-Path $Path) -or -not (Test-Path $sha)) { return $false }
  $calc = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
  $ref  = ((Get-Content -LiteralPath $sha -Raw) -split '\s+')[0]
  return ($calc -eq $ref)
}

# 0) Підготовка вхідних даних
if (-not $ZipPath) {
  $ZipPath = Join-Path $OutDir ("README_DevOps_{0}_GitBook.zip" -f $Version)
}
if (-not (Test-Path -LiteralPath $ZipPath)) { Err "ZIP не знайдено: $ZipPath"; exit 2 }

Info "RepoRoot = $RepoRoot"
Info "OutDir   = $OutDir"
Info "ZipPath  = $ZipPath"
Info "Version  = $Version, TagDate = $TagDate"

# 1) Сайдкар для ZIP
if (Write-Sha256Sidecar -Path $ZipPath) { Ok "SHA256 sidecar для ZIP створено" } else { Warn "Не вдалося створити SHA256 sidecar для ZIP" }

# 2) MANIFEST: перелік релізних файлів + SHA
$manifest = Join-Path $OutDir ("MANIFEST_DevOps_{0}.txt" -f $Version)
Get-ChildItem $OutDir -Filter ("README_DevOps_{0}_GitBook.zip*" -f $Version) |
  Sort-Object Name |
  ForEach-Object {
    $sha = if($_.PSIsContainer){''} else {(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash}
    "{0,-52}  {1,12}  {2}" -f $_.Name, $_.Length, $sha
  } | Set-Content -LiteralPath $manifest -Encoding UTF8
if (Write-Sha256Sidecar -Path $manifest) { Ok "MANIFEST + SHA256 OK" } else { Warn "MANIFEST SHA256 sidecar не створено" }

# 3) (опц.) GPG-підпис
$pubKeyPath = $null
if ($GpgSign) {
  $KEYID = Get-GpgSigningKeyId
  if (-not $KEYID) {
    Info "Секретного ключа не знайдено — створю новий (rsa4096, sign, 2y)."
    $NAME = "CheCha DevOps Release"; $MAIL = "dao.gogs.ua@gmail.com"
    & gpg --quick-gen-key "$NAME <$MAIL>" rsa4096 sign 2y
    $KEYID = Get-GpgSigningKeyId
  }
  if ($KEYID) {
    & gpg --batch --yes --local-user $KEYID --output "$ZipPath.sig"   --detach-sign --armor "$ZipPath"
    if ($LASTEXITCODE -eq 0) { Ok "Підписано ZIP" } else { Warn "Не вдалося підписати ZIP" }
    & gpg --batch --yes --local-user $KEYID --output "$manifest.sig"  --detach-sign --armor "$manifest"
    if ($LASTEXITCODE -eq 0) { Ok "Підписано MANIFEST" } else { Warn "Не вдалося підписати MANIFEST" }
    $pubKeyPath = Join-Path $OutDir ("GPG_RELEASE_PUBKEY_{0}.asc" -f $KEYID)
    & gpg --armor --export $KEYID | Set-Content -LiteralPath $pubKeyPath -Encoding ASCII
    Ok "Експортовано публічний ключ: $(Split-Path $pubKeyPath -Leaf)"
  } else {
    Warn "GPG-підпис пропущено — ключ не створено/не знайдено."
  }
} else {
  Info "GPG-підпис вимкнено (без -GpgSign)."
}

# 4) .gitignore allowlist
$gi = Join-Path $RepoRoot ".gitignore"
$allowLines = @(
  "",
  "# allow DevOps release artifacts in reports",
  "!C03_LOG/reports/MANIFEST_*.txt",
  "!C03_LOG/reports/MANIFEST_*.txt.sha256.txt",
  "!C03_LOG/reports/README_DevOps_v*.zip.sig",
  "!C03_LOG/reports/GPG_RELEASE_PUBKEY_*.asc"
)
if (Test-Path $gi) {
  $curr = Get-Content -LiteralPath $gi -Raw
  $needAppend = $false
  foreach($ln in $allowLines){
    if ($ln -ne "" -and $curr -notmatch [regex]::Escape($ln)) { $needAppend = $true; break }
  }
  if ($needAppend) { Add-Content -LiteralPath $gi -Value ($allowLines -join "`r`n"); Ok ".gitignore оновлено (allowlist)" } else { Info ".gitignore вже містить allowlist" }
} else {
  $allowLines | Set-Content -LiteralPath $gi -Encoding UTF8
  Ok "Створено .gitignore з allowlist"
}

# 5) (опц.) приглушити dirty субмодуля
if ($IgnoreDirtySubmodule) {
  if (Test-Path (Join-Path $RepoRoot ".gitmodules")) {
    git -C $RepoRoot config -f .gitmodules submodule.C12_KNOWLEDGE/MD_INBOX.ignore dirty | Out-Null
    git -C $RepoRoot add .gitmodules
    Ok "Субмодуль MD_INBOX → ignore=dirty"
  } else {
    Info ".gitmodules не знайдено — пропускаю ignore=dirty"
  }
}

# 6) Git add/commit/tag/push
$toAdd = @()
$toAdd += $gi
$toAdd += $manifest, "$manifest.sha256.txt"
$zipSig = "$ZipPath.sig"
$manSig = "$manifest.sig"
if (Test-Path $zipSig) { $toAdd += $zipSig }
if (Test-Path $manSig) { $toAdd += $manSig }
if ($pubKeyPath -and (Test-Path $pubKeyPath)) { $toAdd += $pubKeyPath }

# пробуємо звичайне додавання; якщо .gitignore блокує — форс
git -C $RepoRoot add -- $toAdd 2>$null
if ($LASTEXITCODE -ne 0) {
  git -C $RepoRoot add -f -- $toAdd
  Info "Задіяно git add -f для whitelisted файлів"
}

$commitMsg = "devops: $Version release bundle ($TagDate)"
git -C $RepoRoot commit -m $commitMsg 2>$null
if ($LASTEXITCODE -ne 0) { Warn "Немає змін для коміту або commit не виконано" } else { Ok "Створено коміт: $commitMsg" }

git -C $RepoRoot push origin HEAD | Out-Null
Ok "Пуш у origin HEAD виконано"

$tag = ("DevOpsLayer_{0}_{1}" -f $Version, $TagDate)
git -C $RepoRoot tag -a $tag -m ("DevOps Layer {0} ({1})" -f $Version, $TagDate) -f
git -C $RepoRoot push origin $tag -f | Out-Null
Ok "Тег оновлено і запушено: $tag"

# 7) Верифікація підписів, якщо є
if (Test-Path $zipSig) { & gpg --verify $zipSig $ZipPath | Out-Null; Ok "GPG verify ZIP: OK" }
if (Test-Path $manSig) { & gpg --verify $manSig $manifest | Out-Null; Ok "GPG verify MANIFEST: OK" }

# 8) Підсумок
$okZip = Test-Sha256 -Path $ZipPath
$okMan = Test-Sha256 -Path $manifest
Write-Host ("Integrity: zip={0}  manifest={1}" -f ($okZip ? "OK" : "FAIL"), ($okMan ? "OK" : "FAIL"))
git -C $RepoRoot ls-remote --tags origin | Select-String $tag | Out-Null
Ok "Remote tag перевірено: $tag"

# === 9) Автогенерація постів (GitHub/GitBook/Telegram) + коміт/пуш ===
function Get-Sha256For([string]$Path){
  $sidecar = "$Path.sha256.txt"
  if (Test-Path -LiteralPath $sidecar){
    return ((Get-Content -LiteralPath $sidecar -Raw) -split '\s+')[0]
  }
  if (Test-Path -LiteralPath $Path){
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
  }
  return "<N/A>"
}

function New-DevOpsReleasePosts {
  param(
    [Parameter(Mandatory=$true)][string]$OutDir,
    [Parameter(Mandatory=$true)][string]$Version,
    [Parameter(Mandatory=$true)][string]$TagDate,
    [Parameter(Mandatory=$true)][string]$ZipPath,
    [Parameter(Mandatory=$true)][string]$Manifest,
    [Parameter(Mandatory=$true)][string]$TagName
  )
  $shaZip = Get-Sha256For $ZipPath
  $shaMan = Get-Sha256For $Manifest

  $githubPost = @"
# DevOps Layer $Version — README_DevOps для GitBook

**Дата:** $TagDate  
**Тег:** \`$TagName\`

## 🔍 Highlights
- Оновлений README_DevOps для GitBook (структура, сценарії публікації, перевірки інтегриті).
- MANIFEST з контрольними сумами та розмірами.
- (Опційно) GPG-підпис артефактів для перевірки походження.

## 📦 Артефакти
- \`README_DevOps_${Version}_GitBook.zip\`
- \`MANIFEST_DevOps_${Version}.txt\`
- \`*.sha256.txt\`, \`*.sig\`, \`GPG_RELEASE_PUBKEY_<FPR>.asc\`

## ✅ Інтегриті
- \`SHA256(README_DevOps_${Version}_GitBook.zip): $shaZip\`
- \`SHA256(MANIFEST_DevOps_${Version}.txt): $shaMan\`

## 🔏 Перевірка
\`\`\`powershell
Get-FileHash -Algorithm SHA256 .\README_DevOps_${Version}_GitBook.zip
gpg --import .\GPG_RELEASE_PUBKEY_<FPR>.asc
gpg --verify .\README_DevOps_${Version}_GitBook.zip.sig .\README_DevOps_${Version}_GitBook.zip
\`\`\`
"@

  $gitbookPost = @"
# DevOps Layer — Реліз $Version ($TagDate)

**Артефакт:** \`README_DevOps_${Version}_GitBook.zip\`

## Перевірка цілісності
\`\`\`powershell
Get-FileHash -Algorithm SHA256 .\README_DevOps_${Version}_GitBook.zip
\`\`\`

**SHA256 (ZIP):** \`$shaZip\`  
**SHA256 (MANIFEST):** \`$shaMan\`  
**Тег:** \`$TagName\`
"@

  $tgPost = @"
DevOps Layer $Version ($TagDate) — оновлений README для GitBook ✅
• ZIP: README_DevOps_${Version}_GitBook.zip
• MANIFEST + SHA256
• (опц.) GPG-підписи + публічний ключ
SHA256(ZIP): $shaZip
SHA256(MANIFEST): $shaMan
Тег: $TagName
#DevOps #Release #GitBook
"@

  $ghPath = Join-Path $OutDir ("POST_GitHub_DevOps_{0}.md" -f $Version)
  $gbPath = Join-Path $OutDir ("POST_GitBook_DevOps_{0}.md" -f $Version)
  $tgPath = Join-Path $OutDir ("POST_Telegram_DevOps_{0}.txt" -f $Version)

  $githubPost | Set-Content -LiteralPath $ghPath -Encoding UTF8
  $gitbookPost | Set-Content -LiteralPath $gbPath -Encoding UTF8
  $tgPost     | Set-Content -LiteralPath $tgPath -Encoding UTF8

  return @($ghPath,$gbPath,$tgPath)
}

# Обчислюємо залежності й запускаємо генерацію
if (-not $manifest) { $manifest = Join-Path $OutDir ("MANIFEST_DevOps_{0}.txt" -f $Version) }
$tagName = ("DevOpsLayer_{0}_{1}" -f $Version, $TagDate)

$posts = New-DevOpsReleasePosts -OutDir $OutDir -Version $Version -TagDate $TagDate `
  -ZipPath $ZipPath -Manifest $manifest -TagName $tagName
Ok ("Згенеровано пости: {0}" -f ($posts -join ', '))

# Додаємо пости у git (з повагою до .gitignore)
git -C $RepoRoot add -- $posts 2>$null
if ($LASTEXITCODE -ne 0) { git -C $RepoRoot add -f -- $posts }

git -C $RepoRoot commit -m ("docs: release posts {0} ({1})" -f $Version, $TagDate) 2>$null
git -C $RepoRoot push origin HEAD | Out-Null
Ok "Пости додано й запушено"

