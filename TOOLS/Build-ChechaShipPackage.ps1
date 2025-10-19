<#
.SYNOPSIS
  Збірка релізного ZIP-пакета "Корабель CHECHA": версіонування, MANIFEST (SHA-256),
  CHECKSUMS.txt, CHANGELOG (+Banner meta), README, архівація, .sha256, JSON-summary.

  Підтримує:
    - Роботу від робочої теки (-WorkRoot) або від ZIP (-WorkRootZip) з авто-розпакуванням (TMP cleanup).
    - PS < 7.4 (fallback для відносних шляхів).
    - Опційний git-тег (-GitTag) і GitHub реліз (-GitHubRelease).
    - Пост-крок: .sha256 поруч із ZIP і JSON-підсумок у C03_LOG.
    - SelfTest: сухий прогін без змін (-SelfTest).

.PARAMETER SelfTest
  Сухий прогін: нічого не записує, лише друкує кроки/прогноз версії/імен.
#>

[CmdletBinding()]
param(
    [string]$WorkRoot,
    [string]$WorkRootZip,

    [string]$ExportsRoot = "D:\CHECHA_CORE\EXPORTS",
    [string]$LogsRoot = "D:\CHECHA_CORE\C03_LOG",
    [string]$PackageName = "CHECHA_Ship",
    [string]$Version,                 # опційно (X.Y); якщо не задано — auto-bump з version.txt
    [string]$BannerPath,              # опційно: джерело банера → visuals/CHECHA_Ship_Banner.png
    [switch]$SoftFail,                # не падати на дрібних помилках
    [switch]$GitTag,                  # створити git-тег checha-ship-vX.Y
    [string]$RepoRoot,                # git-репозиторій для тегу/релізу
    [switch]$GitHubRelease,           # створити GitHub реліз через gh
    [switch]$SelfTest                 # сухий прогін
)

# ---------- Helpers ----------
function Die($msg) { Write-Host "[ERR] $msg" -ForegroundColor Red; exit 1 }
function Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }

function Echo-Step($name, $detail) {
    Write-Host ("[SELFTEST] {0}: {1}" -f $name, $detail) -ForegroundColor DarkCyan
}

# Крос-версійне отримання відносного шляху + нормалізація '/' для MANIFEST/CHECKSUMS
function Get-RelPath([string]$Full, [string]$Base) {
    try {
        $rp = Resolve-Path -LiteralPath $Full -Relative -RelativeBasePath $Base -ErrorAction Stop
        return ($rp -replace '\\', '/')
    }
    catch {
        if ($Full.StartsWith($Base, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = $Full.Substring($Base.Length).TrimStart('\', '/')
            return ($rel -replace '\\', '/')
        }
        return ((Split-Path -Path $Full -Leaf) -replace '\\', '/')
    }
}

# Автогенерація README.md
function New-ReadmeChechaShip([string]$OutDir, [string]$Version, [string]$ZipName, [string]$ZipSha256, [string]$ReleaseDate) {
    $readmePath = Join-Path $OutDir "README.md"
    $md = @"
# 🚀 CHECHA Ship v$Version

![CHECHA Ship Banner](visuals/CHECHA_Ship_Banner.png)

---

## ℹ️ Опис
**CHECHA Ship** — стратегічний пакунок матеріалів системи CHECHA_CORE у форматі структурованого ZIP-архіву.
Версія **v$Version** зібрана автоматично з покращеннями і стабілізацією пайплайна.

---

## 📦 Деталі релізу
- **Tag:** \`checha-ship-v$Version\`
- **Дата:** $ReleaseDate
- **Артефакт:** \`$ZipName\`
- **SHA256:**
  \`\`\`
  $ZipSha256
  \`\`\`
- **Файли:** \`MANIFEST.md\`, \`CHECKSUMS.txt\`, \`CHANGELOG.md\`, \`version.txt\`

---

## 🆕 Нове у v$Version
- Auto-bump версії та автоматичне складання ZIP
- \`.sha256\` поруч із релізним архівом
- Summary JSON у \`C03_LOG\`
- Оновлено MANIFEST (SHA-256) та CHECKSUMS
- Очистка тимчасових тек після збірки

---

## 📘 Використання
1. Розпакуй \`$ZipName\` у робочу директорію.
2. Перевір цілісність за допомогою \`CHECKSUMS.txt\` або \`.sha256\`:
   \`\`\`powershell
   Get-FileHash .\$ZipName -Algorithm SHA256
   \`\`\`
3. Вміст організовано для інтеграції з **CHECHA_CORE**.

---

© $(Get-Date -Format 'yyyy') **DAO-GOGS | CHECHA_CORE**
_Зібрано автоматизованим пайплайном._
"@

    if (Test-Path -LiteralPath (Join-Path $OutDir "visuals/CHECHA_Ship_Banner.png")) {
        $md += "`n> _Banner включено до релізу (`visuals/CHECHA_Ship_Banner.png`)._`n"
    }

    Set-Content -Path $readmePath -Encoding UTF8 -Value $md
    return $readmePath
}

# ---------- 0) Ініціалізація логів ----------
New-Item -ItemType Directory -Force -Path $ExportsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $LogsRoot    | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$logFile = Join-Path $LogsRoot ("Build-ChechaShipPackage_{0}.log" -f $stamp)
"[$(Get-Date -Format 'u')] START Build Checha Ship" | Out-File -FilePath $logFile -Encoding UTF8

# ---------- 0.1) Якщо передали ZIP — розпакувати у TMP ----------
if ($WorkRootZip) {
    if (-not (Test-Path -LiteralPath $WorkRootZip)) { Die "WorkRootZip не знайдено: $WorkRootZip" }
    $script:tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("checha_ship_" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Force -Path $script:tmp | Out-Null
    Expand-Archive -Path $WorkRootZip -DestinationPath $script:tmp -Force
    $inner = Get-ChildItem $script:tmp | Where-Object { $_.PSIsContainer } | Select-Object -First 1
    if ($inner) { $WorkRoot = $inner.FullName } else { $WorkRoot = $script:tmp }
    Info "ZIP розпаковано до $WorkRoot" | Tee-Object -FilePath $logFile -Append | Out-Null
}

# ---------- 0.2) Перевірки WorkRoot ----------
if (-not $WorkRoot) { Die "Не вказано WorkRoot/WorkRootZip" }
if (!(Test-Path -LiteralPath $WorkRoot)) { Die "WorkRoot не знайдено: $WorkRoot" }

# ---------- SelfTest: ранній вихід з прогнозом ----------
if ($SelfTest) {
    Echo-Step "Input"   ("WorkRoot={0}; WorkRootZip={1}" -f $WorkRoot, $WorkRootZip)
    Echo-Step "Outputs" ("ExportsRoot={0}; LogsRoot={1}" -f $ExportsRoot, $LogsRoot)

    $predVersion = $Version
    if (-not $predVersion) {
        $versionTxt = Join-Path $WorkRoot "version.txt"
        if (Test-Path $versionTxt) {
            $first = (Get-Content $versionTxt -TotalCount 1).Trim()
            if ($first -match 'v(\d+)\.(\d+)') {
                $maj = [int]$Matches[1]; $min = [int]$Matches[2] + 1
                $predVersion = "{0}.{1}" -f $maj, $min
            }
            else { $predVersion = "1.0" }
        }
        else { $predVersion = "1.0" }
    }
    $predTag = "checha-ship-v$predVersion"
    $predOutDirName = "{0}_v{1}" -f $PackageName, $predVersion
    $predZipName = "{0}_v{1}.zip" -f $PackageName, $predVersion
    $predZipPath = Join-Path $ExportsRoot $predZipName

    Echo-Step "Version" ("tag={0}; outDir={1}; zip={2}" -f $predTag, $predOutDirName, $predZipPath)
    if ($GitTag) { Echo-Step "Planned" "Git tag + push in $RepoRoot" }
    if ($GitHubRelease) { Echo-Step "Planned" "GitHub release via gh" }
    if ($BannerPath) { Echo-Step "Planned" "Copy banner → visuals/CHECHA_Ship_Banner.png" }
    Echo-Step "Planned" "Update version.txt, CHANGELOG.md, MANIFEST.md, CHECKSUMS.txt, README.md, ZIP, .sha256, JSON summary"
    Echo-Step "Exit"    "SelfTest completed"
    exit 0
}

# ---------- 1) Визначення версії ----------
$versionTxt = Join-Path $WorkRoot "version.txt"
if (-not $Version) {
    if (Test-Path -LiteralPath $versionTxt) {
        $first = (Get-Content $versionTxt -TotalCount 1).Trim()
        if ($first -match 'v(\d+)\.(\d+)') {
            $maj = [int]$Matches[1]; $min = [int]$Matches[2] + 1
            $Version = "{0}.{1}" -f $maj, $min
            Info "Підвищую версію: $($Matches[0]) -> v$Version" | Tee-Object -FilePath $logFile -Append | Out-Null
        }
        else {
            $Version = "1.0"
            Warn "Не розпізнав поточну версію у version.txt — беру v$Version" | Tee-Object -FilePath $logFile -Append | Out-Null
        }
    }
    else {
        $Version = "1.0"
        Warn "version.txt відсутній — беру v$Version" | Tee-Object -FilePath $logFile -Append | Out-Null
    }
}
$tag = "checha-ship-v$Version"
$outDirName = "{0}_v{1}" -f $PackageName, $Version
$outDir = Join-Path (Split-Path -Parent $WorkRoot) $outDirName

# ---------- 2) Робоча копія ----------
if (Test-Path -LiteralPath $outDir) { Remove-Item -Recurse -Force $outDir }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Copy-Item -Recurse -Force -Path (Join-Path $WorkRoot '*') -Destination $outDir

# ---------- 3) Банер (опційно) ----------
$visualsDir = Join-Path $outDir "visuals"
New-Item -ItemType Directory -Force -Path $visualsDir | Out-Null
$targetBanner = Join-Path $visualsDir "CHECHA_Ship_Banner.png"
if ($BannerPath) {
    if (Test-Path -LiteralPath $BannerPath) {
        Copy-Item -Force -LiteralPath $BannerPath -Destination $targetBanner
        Info "Банер вставлено: $targetBanner" | Tee-Object -FilePath $logFile -Append | Out-Null
    }
    else {
        $msg = "BannerPath не знайдено: $BannerPath"
        if ($SoftFail) { Warn $msg | Tee-Object -FilePath $logFile -Append | Out-Null } else { Die $msg }
    }
}
elseif (!(Test-Path -LiteralPath $targetBanner)) {
    Warn "Банер відсутній (visuals/CHECHA_Ship_Banner.png). Продовжую…" | Tee-Object -FilePath $logFile -Append | Out-Null
}

# ---------- 4) Оновити version.txt ----------
$today = Get-Date -Format 'yyyy-MM-dd'
$versionBody = "$tag`n$today`n"
Set-Content -Path (Join-Path $outDir "version.txt") -Encoding UTF8 -Value $versionBody

# --- Banner meta (якщо є) ---
$bannerNote = $null
$bannerRel = "visuals/CHECHA_Ship_Banner.png"
$bannerAbs = Join-Path $outDir $bannerRel
if (Test-Path -LiteralPath $bannerAbs) {
    try {
        $bannerSha = (Get-FileHash -LiteralPath $bannerAbs -Algorithm SHA256).Hash.ToLower()
        $bannerLen = (Get-Item -LiteralPath $bannerAbs).Length
        $bannerNote = "- Banner: `$bannerRel` (size: $bannerLen bytes, sha256: $bannerSha)"
    }
    catch {
        $bannerNote = "- Banner: `$bannerRel` (sha256: n/a)"
    }
}

# ---------- 5) Оновити CHANGELOG.md (prepend) ----------
$chlog = Join-Path $outDir "CHANGELOG.md"
$header = "# CHANGELOG — CHECHA Ship"
$newEntryLines = @(
    "## v$Version — $today",
    "- Реліз пакета: $outDirName",
    "- Оновлено MANIFEST (SHA-256), CHECKSUMS і ZIP-архів."
)
if ($bannerNote) { $newEntryLines += $bannerNote }
$newEntry = $newEntryLines -join "`n"

if (Test-Path -LiteralPath $chlog) {
    $old = (Get-Content $chlog -Raw)
    if ($old -notmatch '^\s*#\s*CHANGELOG') { $old = "$header`n`n$old" }
    Set-Content -Path $chlog -Encoding UTF8 -Value "$header`n`n$newEntry`n$old"
}
else {
    Set-Content -Path $chlog -Encoding UTF8 -Value "$header`n`n$newEntry`n"
}

# ---------- 6) MANIFEST.md + CHECKSUMS.txt ----------
$manifestPath = Join-Path $outDir "MANIFEST.md"
$checksPath = Join-Path $outDir "CHECKSUMS.txt"

$files = Get-ChildItem -Path $outDir -Recurse -File | Sort-Object FullName
$rows = @()
$checks = @()

foreach ($f in $files) {
    $rel = Get-RelPath -Full $f.FullName -Base $outDir
    $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
    $rows += "| $rel | $($f.Length) | `$hash` |"
    $checks += "$hash *$rel"
}

$manifest = @("# MANIFEST — $outDirName", "", "| file | size_bytes | sha256 |", "|---|---:|---|") + $rows
Set-Content -Path $manifestPath -Encoding UTF8  -Value ($manifest -join "`n")
Set-Content -Path $checksPath   -Encoding ASCII -NoNewline -Value (($checks -join "`r`n") + "`r`n")

# ---------- 7) Збірка ZIP ----------
$zipName = "{0}_v{1}.zip" -f $PackageName, $Version
$zipPath = Join-Path $ExportsRoot $zipName
if (Test-Path -LiteralPath $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zipPath -Force

# ---------- 8) Підсумок ----------
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower()
$sum = @"
--- SUMMARY ---
Tag:        $tag
OutDir:     $outDir
ZIP:        $zipPath
ZIP_SHA256: $zipHash
Timestamp:  $(Get-Date -Format 'u')
"@
$sum | Tee-Object -FilePath $logFile -Append | Out-Host

# ---------- 8.1) README.md ----------
try {
    $readmeMade = New-ReadmeChechaShip -OutDir $outDir -Version $Version -ZipName $zipName -ZipSha256 $zipHash -ReleaseDate $today
    Info "README.md згенеровано: $readmeMade" | Tee-Object -FilePath $logFile -Append | Out-Null
}
catch {
    Warn "Не вдалося згенерувати README.md: $($_.Exception.Message)" | Tee-Object -FilePath $logFile -Append | Out-Null
}

# ---------- 9) Опційно: Git-тег і GitHub-реліз ----------
if ($GitTag -or $GitHubRelease) {
    if (-not $RepoRoot) {
        Warn "GitTag/GitHubRelease увімкнено, але RepoRoot не вказано — пропускаю" | Tee-Object -FilePath $logFile -Append | Out-Null
    }
    else {
        Push-Location $RepoRoot
        try {
            git rev-parse --is-inside-work-tree 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Не git-репозиторій: $RepoRoot" }

            if ($GitTag) {
                git tag -a $tag -m "Release $tag" 2>$null
                if ($LASTEXITCODE -ne 0) {
                    Warn "Тег $tag вже існує або помилка створення — пропускаю" | Tee-Object -FilePath $logFile -Append | Out-Null
                }
                else {
                    git push origin $tag | Out-Null
                    Info "Тег запушено: $tag" | Tee-Object -FilePath $logFile -Append | Out-Null
                }
            }

            if ($GitHubRelease) {
                $cmd = "gh release create `"$tag`" `"$zipPath`" --title `"$tag`" --notes `"$outDirName`""
                Info "gh release: $cmd" | Tee-Object -FilePath $logFile -Append | Out-Null
                try {
                    & gh release create $tag $zipPath --title $tag --notes $outDirName | Out-Null
                    Info "GitHub реліз створено." | Tee-Object -FilePath $logFile -Append | Out-Null
                }
                catch {
                    Warn "Не вдалось створити GitHub реліз (gh). Деталі: $($_.Exception.Message)" | Tee-Object -FilePath $logFile -Append | Out-Null
                }
            }
        }
        catch {
            Warn $_.Exception.Message | Tee-Object -FilePath $logFile -Append | Out-Null
        }
        finally {
            Pop-Location
        }
    }
}

# ---------- 9.1) Пост-крок: .sha256 поруч із ZIP + JSON summary у C03_LOG ----------
try {
    $zipSha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower()
    Set-Content -Path ($zipPath + ".sha256") -Encoding ASCII -Value "$zipSha *$(Split-Path $zipPath -Leaf)"
    Info "SHA256 записано: $zipSha" | Tee-Object -FilePath $logFile -Append | Out-Null
}
catch {
    Warn "Не вдалося згенерувати .sha256: $($_.Exception.Message)" | Tee-Object -FilePath $logFile -Append | Out-Null
}

try {
    $summary = [pscustomobject]@{
        Tag       = $tag
        OutDir    = $outDir
        Zip       = $zipPath
        ZipSHA256 = $zipSha
        Timestamp = (Get-Date -Format 'u')
    }
    $jsonPath = Join-Path $LogsRoot ("Build-ChechaShipPackage_{0}.json" -f $stamp)
    $summary | ConvertTo-Json -Depth 5 | Set-Content $jsonPath -Encoding UTF8
    Info "Summary JSON: $jsonPath" | Tee-Object -FilePath $logFile -Append | Out-Null
}
catch {
    Warn "Не вдалося записати Summary JSON: $($_.Exception.Message)" | Tee-Object -FilePath $logFile -Append | Out-Null
}

# ---------- 10) Прибирання TMP після WorkRootZip ----------
if ($WorkRootZip -and (Get-Variable -Name tmp -Scope Script -ErrorAction SilentlyContinue)) {
    if (Test-Path $script:tmp) {
        try {
            Remove-Item -Recurse -Force $script:tmp
            Info "TMP очищено: $script:tmp" | Tee-Object -FilePath $logFile -Append | Out-Null
        }
        catch {
            Warn "Не вдалося видалити TMP ($script:tmp): $($_.Exception.Message)" | Tee-Object -FilePath $logFile -Append | Out-Null
        }
    }
}

Info "Готово." | Tee-Object -FilePath $logFile -Append | Out-Null
exit 0

