# Daily Focus System (v1.2)

Цей пакет містить:
- **Create-DailyFocus.ps1** — основний скрипт (оновлення Dashboard, Timeline, RestoreLog, Changelog, перевірка SHA256).
- **README_FocusGuide.md** — короткий гайд-шпаргалка.

## Основні параметри
- `-UpdateStatus` — оновлює Dashboard / Timeline / RestoreLog
- `-UpdateChangelog` — робить запис у CHANGELOG
- `-NewVersion` — створює нову версію з SHA256 та підписом
- `-VerifyChecksums` — перевіряє контрольні суми
- `-AutoFix` — з `-VerifyChecksums` перезаписує правильні SHA256
- `-RegisterTasks` — створює завдання CheCha-Focus-Morning та CheCha-Focus-Evening
- `-PassThru` — повертає об'єкт з шляхами

## Приклади запуску
```powershell
pwsh -File "Create-DailyFocus.ps1" -Root "D:\CHECHA_CORE\C06_FOCUS" -UpdateStatus
pwsh -File "Create-DailyFocus.ps1" -Root "D:\CHECHA_CORE\C06_FOCUS" -NewVersion
pwsh -File "Create-DailyFocus.ps1" -Root "D:\CHECHA_CORE\C06_FOCUS" -VerifyChecksums
pwsh -File "Create-DailyFocus.ps1" -Root "D:\CHECHA_CORE\C06_FOCUS" -VerifyChecksums -AutoFix
```

✍️ С.Ч.
