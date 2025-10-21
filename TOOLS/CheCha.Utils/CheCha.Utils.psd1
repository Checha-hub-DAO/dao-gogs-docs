@{
  RootModule        = 'CheCha.Utils.psm1'
  ModuleVersion     = '1.0.0'
  GUID              = 'b6d1a1a1-8b1a-4f9a-95b1-cc0b0d8df111'
  Author            = 'S.Ch.'
  CompanyName       = 'CHECHA_CORE'
  Description       = 'Utility functions for CHECHA CORE / DAO-GOGS scripts'
  PowerShellVersion = '5.1'
  FunctionsToExport = @(
    'Log','Fail','Ensure-Dir','Get-IsoWeekStartEnd',
    'Read-FrontMatterVersion','Get-LastArtifacts','Send-Telegram'
  )
  AliasesToExport   = @()
  CmdletsToExport   = @()
  PrivateData       = @{}
}
