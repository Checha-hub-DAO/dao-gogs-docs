# === AUTO_COMMIT_EXIT_PATH.ps1 ===
$ErrorActionPreference = "Stop"

# --- Налаштування ---
$RepoRoot  = "D:\CHECHA_CORE"
$TargetDir = Join-Path $RepoRoot "C06_FOCUS\EXIT_PATH"
$LogFile   = Join-Path $RepoRoot "C03_LOG\reports\C03_LOG_report_EXIT_MANIFEST_COMPLETE_2025-10-23.md"
$Author    = "С.Ч."
$Branch    = "main"

function Write-Info($msg, $color="Cyan"){ Write-Host $msg -ForegroundColor $color }

# --- Перевірки ---
if (-not (Test-Path $RepoRoot)) { throw "Repo path not found: $RepoRoot" }
if (-not (Test-Path $TargetDir)) { throw "Target path not found: $TargetDir" }

# Git наявність
try { git --version | Out-Null } catch { throw "Git не знайдено у PATH" }

# --- Вибір файлів (тільки EXIT_PATH, потрібні розширення) ---
$patterns = @("*.md","*.pdf","*.png","*.zip","*.sha256.txt")
$files = foreach ($p in $patterns) { Get-ChildItem -Path $TargetDir -Filter $p -Recurse -File -ErrorAction SilentlyContinue }

if (-not $files -or $files.Count -eq 0) {
  Write-Info "[AUTO] Немає файлів під вибірку у $TargetDir" "Yellow"
  exit 0
}

# --- git add тільки з вибірки ---
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
$commitMsg = "auto: EXIT_PATH sync ($now) [$Author]"
Write-Info "[GIT] Commit -> $commitMsg" "Green"
git -C $RepoRoot commit -m $commitMsg

Write-Info "[GIT] Push -> origin/$Branch" "Green"
git -C $RepoRoot push origin $Branch

# --- Логування у C03_LOG ---
$logBlock = @"
[OK] AUTO_COMMIT: EXIT_PATH синхронізовано.
Коміт: $commitMsg
Каталог: C06_FOCUS/EXIT_PATH
Дата: $now
Автор: $Author
"@
Add-Content -Encoding UTF8 $LogFile $logBlock

Write-Info "`n✅ AUTO_COMMIT завершено успішно." "Green"
