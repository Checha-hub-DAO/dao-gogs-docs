@echo off
REM === EDIT THESE TWO LINES FOR EACH RELEASE ===
set "BASE=D:\CHECHA_CORE\C11\SHIELD4_ODESA"
set "ZIP=C:\Users\serge\Downloads\SHIELD4_ODESA_UltimatePack_vX.Y.zip"
set "VER=vX.Y"
REM ============================================

set "PS1=%~dp0Manage_Shield4_Release_v2_fixed2.ps1"

REM Optional modules to drop into Modules\ (add/remove as needed)
set "M1=C:\Users\serge\Downloads\SHIELD4_ODESA_MegaPack_v1.0.zip"
set "M2=C:\Users\serge\Downloads\SHIELD4_ODESA_MegaVisualPack_v1.0.zip"
set "M3=C:\Users\serge\Downloads\SHIELD4_ODESA_MegaPack_PrintBook_v1.1.pdf"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -BaseDir "%BASE%" -NewReleasePath "%ZIP%" -Version "%VER%" -ModulesToAdd "%M1%" "%M2%" "%M3%"
pause
