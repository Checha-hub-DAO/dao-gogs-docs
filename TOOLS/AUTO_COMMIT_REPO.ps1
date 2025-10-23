# === AUTO_COMMIT_REPO.ps1 ===
$ErrorActionPreference = "Stop"

# --- Налаштування ---
$RepoRoot = "D:\CHECHA_CORE"
$Branch   = "main"
$Author   = "С.Ч."
$LogFile  = Join-Path $RepoRoot "C03_LOG\reports\C03_LOG_report_EXIT_MANIFEST_COMPLETE_2025-10-23.md"

# Білий список розширень (додай/прибери за потреби)
$AllowExt = @(".md",".pdf",".png",".jpg",".jpeg",".gif",".svg",".zip",".sha256",".sha256.txt",".json",".yml",".yaml",".ps1",".bat",".psm1",".css")

function Write-Info($msg, $color="Cyan"){ Write-Host $msg -ForegroundColor $color }

# --- Перевірки ---
if (-not (Test-Path $RepoRoot)) { throw "Repo path not found: $RepoRoot" }
try { git --version | Out-Null } catch { throw "Git не знайдено у PATH" }

# --- Підібрати файли за білим списком по всьому репо ---
$files = Get-ChildItem -Path $RepoRoot -Recurse -File -ErrorAction SilentlyContinue |
         Where-Object { $AllowExt -contains ([System.IO.Path]::GetExtension($_.FullName).ToLower()) }

if (-not $files -or $files.Count -eq 0) {
  Write-Info "[AUTO] Немає файлів під вибірку у всьому репозиторії." "Yellow"
  exit 0
}

# --- git add тільки дозволені файли (відносні шляхи) ---
foreach ($f in $files) {
  $rel = $f.FullName.Substring($RepoRoot.Length).TrimStart('\','/')
  git -C $RepoRoot add -- "$rel"
}

# --- Перевірити, чи є що комітити ---
$st = git -C $RepoRoot status --porcelain
if ([string]::IsNullOrWhiteSpace($st)) {
  Write-Info "[AUTO] Змін немає. Все актуально." "Yellow"
  exit 0
}

# --- Коміт і пуш ---
$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$commitMsg = "auto: repo sync ($now) [$Author]"
Write-Info "[GIT] Commit -> $commitMsg" "Green"
git -C $RepoRoot commit -m $commitMsg

Write-Info "[GIT] Push -> origin/$Branch" "Green"
git -C $RepoRoot push origin $Branch

# --- Лог ---
$logBlock = @"
[OK] AUTO_COMMIT_REPO: синхронізовано весь репозиторій.
Коміт: $commitMsg
Гілка: $Branch
Дата: $now
Автор: $Author
"@
Add-Content -Encoding UTF8 $LogFile $logBlock

Write-Info "`n✅ AUTO_COMMIT_REPO завершено успішно." "Green"
