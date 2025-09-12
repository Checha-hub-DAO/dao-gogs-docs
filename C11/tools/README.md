# C11/tools — README

## Cleanup-C11-Tools

- Автоматизує чистку, архівування і нормалізацію скриптів.
- Лог: C03/LOG/cleanup_tools.log
- Архіви: C05/ARCHIVE/scripts_cleanup_*/
- Індекс: TOOLS_INDEX.md

### Приклади запуску
```powershell
pwsh -NoProfile -File .\Cleanup-c11-tools.ps1 -Root 'D:\CHECHA_CORE' -WhatIf -DryRun
pwsh -NoProfile -File .\Cleanup-c11-tools.ps1 -Root 'D:\CHECHA_CORE'
pwsh -NoProfile -File .\Cleanup-c11-tools.ps1 -Root 'D:\CHECHA_CORE' -NormalizeNames -Confirm:$false
```


