@{
    RootModule        = 'Utils.Core.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'c64c9d1a-88f3-44f4-9c3b-5a1d0a3d8a21'
    Author            = 'С.Ч.'
    CompanyName       = 'DAO-GOGS'
    Copyright         = '(c) С.Ч.'
    PowerShellVersion = '5.1'
    Description       = 'CHECHA_CORE: утиліти ядра (TZ Europe/Kyiv, логери, git/gh, аудит)'
    FunctionsToExport = @(
        'Get-KyivDate','Info','Warn','Err','Die',
        'Start-Op','Stop-Op','Write-AuditLog',
        'Ensure-GitRepo','Get-RepoSlug',
        'Disable-GhPager','Invoke-Gh',
        'Compute-WeekBlock'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @('_Info','_Warn','_Err','_Die')
    PrivateData       = @{ PSData = @{ Tags = @('CHECHA','Core','Utils') } }
}
