
CHECHA CORE — C11\tools suite (cleanup + health + register)
===========================================================

Файли всередині архіву:
- Cleanup-c11-tools.ps1                 — чистка C11\tools (інвентаризація, архів варіантів, INDEX, README, лог)
- Check-C11-ToolsHealth.ps1             — health-чекер (README, INDEX, лог, архів/sha256, задача)
- Register-CleanupToolsTask_v2.ps1      — реєстрація через schtasks (потребує правильних лапок)
- Register-CleanupToolsTask_API.ps1     — реєстрація через PowerShell API (рекомендовано)

Куди класти:
  D:\CHECHA_CORE\C11\tools\

Базові команди:
  # Чистка
  pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\CHECHA_CORE\C11\tools\Cleanup-c11-tools.ps1" -Root "D:\CHECHA_CORE"

  # Health
  pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\CHECHA_CORE\C11\tools\Check-C11-ToolsHealth.ps1" -Root "D:\CHECHA_CORE"

  # Реєстратор (API, безпечний)
  pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\CHECHA_CORE\C11\tools\Register-CleanupToolsTask_API.ps1" -Root "D:\CHECHA_CORE" -DayOfWeek Sunday -Hour 21 -Minute 0

  # Реєстратор (schtasks, якщо дуже треба)
  pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\CHECHA_CORE\C11\tools\Register-CleanupToolsTask_v2.ps1" -Root "D:\CHECHA_CORE" -Day SUN -Hour 21 -Minute 0

Примітки:
- Якщо у поточній чистці не було варіантів — порожню сесію архіву не створюємо; health це враховує.
- Імена скриптів нечутливі до регістру у Windows, але скрипти наведено з узгодженими назвами.
- Для перших прогонів бажано запускати cleanup у -WhatIf -DryRun, потім — без них.
- Логи: D:\CHECHA_CORE\C03\LOG\cleanup_tools.log та cleanup_health.log
