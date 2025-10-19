# Wrapper для щотижневої збірки CHECHA_Ship
$ErrorActionPreference = "Stop"

$tool = "D:\CHECHA_CORE\TOOLS\Build-ChechaShipPackage.ps1"

& $tool `
    -WorkRootZip "D:\CHECHA_CORE\CHECHA_Ship\CHECHA_Ship_v1.0.zip" `
    -ExportsRoot "D:\CHECHA_CORE\EXPORTS" `
    -LogsRoot "D:\CHECHA_CORE\C03_LOG" `
    -PackageName "CHECHA_Ship" `
    -SoftFail  | Tee-Object -FilePath "D:\CHECHA_CORE\C03_LOG\CHECHA-Ship-Release_run.log" -Append


