# === Commit-PORTAL_LIGHT_v1.0.ps1 ===
$repoRoot   = "D:\CHECHA_CORE"
$summary    = "C06_FOCUS/EXIT_PATH/PORTAL_LIGHT_v1.0_SUMMARY.md"
$logReport  = "D:\CHECHA_CORE\C03_LOG\reports\C03_LOG_report_EXIT_MANIFEST_COMPLETE_2025-10-23.md"
$commitMsg  = "exit: PORTAL_LIGHT v1.0 summary added (C06_FOCUS/EXIT_PATH) [S.Ch.]"

Write-Host "=== PORTAL_LIGHT v1.0 :: Commit & Log ===" -ForegroundColor Cyan

if (-not (Test-Path (Join-Path $repoRoot $summary))) {
    Write-Host "[ERR] Не знайдено файл $summary — перевір шлях." -ForegroundColor Red
    exit 1
}

git -C $repoRoot add $summary
git -C $repoRoot commit -m $commitMsg
git -C $repoRoot push origin main

$date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -Encoding UTF8 $logReport @"
[OK] PORTAL_LIGHT v1.0 summary зафіксовано у GitBook.
Файл: $summary
Коміт: $commitMsg
Дата: $date
Автор: С.Ч.
"@

Write-Host "`n✅ Успішно завершено: PORTAL_LIGHT v1.0 синхронізовано та зафіксовано." -ForegroundColor Green
