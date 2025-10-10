param(
  [switch]$AlsoLatest = $true,
  [int]$Keep = 14,
  [string]$FocusDir = "D:\CHECHA_CORE\C06_FOCUS",
  [switch]$WriteRestoreLog = $true,
  [string]$RestoreLogPath = "D:\CHECHA_CORE\C06_FOCUS\FOCUS_RestoreLog.md"
)
$ErrorActionPreference = "Stop"

function Set-ChecklistStatus {
  param(
    [Parameter(Mandatory)][ValidateSet('OPEN','IN-PROGRESS','DONE')][string]$Status,
    [Parameter(Mandatory)][string]$Path
  )
  if (-not (Test-Path $Path)) { throw "File not found: $Path" }
  $lines = Get-Content -Path $Path -Encoding UTF8
  if ($lines.Count -eq 0) { throw "File is empty: $Path" }

  # Шукаємо існуючий рядок статусу на перших 5 рядках
  $idx = ($lines | Select-Object -First 5 |
          ForEach-Object { $_ } |
          ForEach-Object { $_ } | ForEach-Object { $_ }) | Out-Null
  $statusIdx = -1
  for ($i=0; $i -lt [Math]::Min(5, $lines.Count); $i++) {
    if ($lines[$i] -match '^\s*(?:>\s*)?Status:\s*(OPEN|IN-PROGRESS|DONE)\s*$') { $statusIdx = $i; break }
  }
  $new = "Status: $Status"
  if ($statusIdx -ge 0) { $lines[$statusIdx] = $new } else { $lines = @($new) + $lines }
  $lines | Set-Content -Path $Path -Encoding utf8BOM
}

# --- Шляхи
$today       = Get-Date -Format "yyyy-MM-dd"
$stamp       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$targetDir   = $FocusDir
$datedPath   = Join-Path $targetDir ("CHECKLIST_{0}.md" -f $today)
$latestPath  = Join-Path $targetDir "TODAY_CHECKLIST.md"
$logPath     = Join-Path $targetDir "CHECKLIST_LOG.md"

# --- Тека
if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir | Out-Null }

# --- Контент (додаємо заголовок без статусу — статус допишемо функцією нижче)
$md = @"
# Оперативний чек-лист на $today

## 🔹 Git / Репозиторій
- [ ] Перевірити `git remote -v` → чи правильно прописаний `origin`.
- [ ] Якщо некоректно → виконати:
  ```powershell
  git remote remove origin
  git remote add origin https://github.com/Checha-hub/<repo>.git
  git push -u origin main
