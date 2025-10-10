pwsh -NoProfile -ExecutionPolicy Bypass `
  -File "D:\CHECHA_CORE\TOOLS\Generate-WeeklyChecklistReport.ps1" `
  -RestoreLogPath "D:\CHECHA_CORE\C06_FOCUS\FOCUS_RestoreLog.md" `
  -ReportsRoot "D:\CHECHA_CORE\REPORTS" `
  -GitPublish -GitBranch reports -RemoteName origin -Open
