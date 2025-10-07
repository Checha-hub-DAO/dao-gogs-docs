@echo off
set "BASE=D:\CHECHA_CORE\C11\SHIELD4_ODESA"
set "ZIP=C:\Users\serge\Downloads\SHIELD4_ODESA_UltimatePack_v2.6.zip"
set "VER=v2.6"
set "PS1=%~dp0Manage_Shield4_Release_v2_fixed2.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -BaseDir "%BASE%" -NewReleasePath "%ZIP%" -Version "%VER%" -ModulesToAdd "C:\Users\serge\Downloads\SHIELD4_ODESA_MegaPack_v1.0.zip" "C:\Users\serge\Downloads\SHIELD4_ODESA_MegaVisualPack_v1.0.zip" "C:\Users\serge\Downloads\SHIELD4_ODESA_MegaPack_PrintBook_v1.1.pdf"
pause
