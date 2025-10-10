param(
  [Parameter(Mandatory)][string]$ZipPath,  # шлях до релізного ZIP
  [Parameter(Mandatory)][string]$ArchiveDir,  # тека архіву року
  [string]$ArchiveLogPath,  # шлях до ARCHIVE_LOG_YYYY.md (необов’язково)
  [string]$Version = "v1.0",
  [string]$ReleaseDate = (Get-Date -Format 'yyyy-MM-dd'),
  [string]$Status = "✅ Stable",
  [string]$Notes = ""
)

if(-not (Test-Path -LiteralPath $ZipPath)){ throw "ZIP not found: $ZipPath" }
if(-not (Test-Path -LiteralPath $ArchiveDir)){ New-Item -ItemType Directory -Force -Path $ArchiveDir | Out-Null }

$zipName = Split-Path $ZipPath -Leaf
$dst = Join-Path $ArchiveDir $zipName

Copy-Item -LiteralPath $ZipPath -Destination $dst -Force

$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $dst).Hash.ToLower()
Write-Host "Copied -> $dst" -ForegroundColor Green
Write-Host "SHA256 -> $sha" -ForegroundColor Green

# Якщо задано шлях до журналу — додаємо рядок
if($ArchiveLogPath){
  if(-not (Test-Path -LiteralPath $ArchiveLogPath)){
    # створимо каркас файлу, якщо його немає
    @(
      "# 🗂️ Архів звітів CheCha System — $($ReleaseDate.Substring(0,4))",
      "**Куратор:** С.Ч.",
      "",
      "## 📦 Поточний цикл релізів",
      "| № | Дата | Назва пакета | Версія | Хеш SHA-256 | Статус | Примітки |",
      "|---|------|---------------|---------|--------------|---------|-----------|"
    ) | Set-Content -Encoding UTF8 -LiteralPath $ArchiveLogPath
  }
  # авто-номер: підрахувати існуючі рядки-елементи
  $rows = (Get-Content -LiteralPath $ArchiveLogPath) | Where-Object { $_ -match '^\|\s*\d+\s*\|' }
  $n = ($rows.Count + 1)
  $row = "| $n | $ReleaseDate | $zipName | $Version | $sha | $Status | $Notes |"
  Add-Content -Encoding UTF8 -LiteralPath $ArchiveLogPath -Value $row
  Write-Host "ARCHIVE_LOG updated: $ArchiveLogPath" -ForegroundColor Cyan
}

# код виходу 0 якщо все ОК
exit 0
