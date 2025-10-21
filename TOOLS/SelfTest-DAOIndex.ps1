pwsh -NoProfile -File D:\CHECHA_CORE\TOOLS\Build-DAOIndexPackage.ps1 -UseStaging -VerboseSummary
pwsh -NoProfile -File D:\CHECHA_CORE\TOOLS\Build-DAOIndexPackage.ps1 -UseStaging -NotifyPublic
try {
  pwsh -NoProfile -File D:\CHECHA_CORE\TOOLS\Build-DAOIndexPackage.ps1 -ArchitectureDir "D:\nope"
} catch { "NEGATIVE OK: $($_.Exception.Message)" }
