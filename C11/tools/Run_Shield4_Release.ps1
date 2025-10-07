<#
.SYNOPSIS
  Запуск релізу SHIELD4 з готовим списком модулів.
.DESCRIPTION
  Це допоміжний скрипт. Ти лише міняєш:
    - $Version
    - $NewReleasePath
    - список $mods
  А решта параметрів і логіка вже готові.
#>

# --- Налаштування ---
$BaseDir        = 'D:\CHECHA_CORE\C11\SHIELD4_ODESA'
$Version        = 'v2.6'
$NewReleasePath = 'C:\Users\serge\Downloads\SHIELD4_ODESA_UltimatePack_v2.6.zip'

# Модулі для включення
$mods = @(
  'C:\Users\serge\Downloads\SHIELD4_ODESA_MegaPack_v1.0.zip',
  'C:\Users\serge\Downloads\SHIELD4_ODESA_MegaVisualPack_v1.0.zip'
)

# Додатково: якщо є нотатки
#$ReleaseNotes = 'C:\Users\serge\Docs\SHIELD4_ODESA_ReleaseNotes_v2.6.md'

# --- Запуск (спершу симуляція) ---
& "$BaseDir\..\tools\Manage_Shield4_Release.ps1" `
  -BaseDir $BaseDir `
  -NewReleasePath $NewReleasePath `
  -Version $Version `
  -ModulesToAdd $mods `
  -AutoPickPrintBook `
  -SkipMissing `
  -ExtractZip `
  -Verbose -WhatIf

# --- Бойовий запуск (розкоментуй, коли все ок) ---
# & "$BaseDir\..\tools\Manage_Shield4_Release.ps1" `
#   -BaseDir $BaseDir `
#   -NewReleasePath $NewReleasePath `
#   -Version $Version `
#   -ModulesToAdd $mods `
#   -AutoPickPrintBook `
#   -SkipMissing `
#   -ExtractZip `
#   -Verbose
