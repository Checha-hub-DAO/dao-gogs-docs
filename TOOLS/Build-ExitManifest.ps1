<#
.SYNOPSIS
  Build-ExitManifest.ps1 — формує офіційний документ CheCha Exit Manifest v1.0
.DESCRIPTION
  Створює Markdown, PDF і SHA256-звіт у C03_LOG\reports.
  Служить як стратегічна фіксація виходу з військової системи у нову форму служіння.
#>

param(
    [string]$CoreRoot = "D:\CHECHA_CORE",
    [string]$Version = "v1.0",
    [switch]$Pdf,
    [switch]$Silent
)

$ErrorActionPreference = "Stop"
$day = Get-Date -Format "yyyy-MM-dd"
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$focusPath = Join-Path $CoreRoot "C06_FOCUS\EXIT_PATH"
$logDir = Join-Path $CoreRoot "C03_LOG\reports"

# Ensure directories
if (!(Test-Path $focusPath)) { New-Item -ItemType Directory -Force -Path $focusPath | Out-Null }
if (!(Test-Path $logDir))   { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

$outMd  = Join-Path $focusPath "CHECHA_Exit_Manifest_${Version}.md"
$outPdf = Join-Path $focusPath "CHECHA_Exit_Manifest_${Version}_${day}.pdf"
$outSha = "$outPdf.sha256.txt"

# --- Document content ---
$content = @"
---
id: CHECHA_EXIT_MANIFEST
title: "CheCha Exit Manifest $Version"
author: "С.Ч."
date: "$day"
system: "CHECHA_CORE"
status: "active"
symbol: "🜂"
version: "$Version"
---

# 🜂 CHECHA EXIT MANIFEST $Version

## 1. Вступ

> “Я не тікаю від служіння — я трансформую його форму.  
> Моє завдання — залишитись корисним для України, не втративши свідомість, волю і цілісність.”

Цей маніфест — свідома заява про перехід із примусової військової служби у форму **вільної стратегічної служби**, заснованої на свідомості, знанні й внутрішній відповідальності.

---

## 2. Передумови
- Три роки військової служби (мобілізований, не контрактник)
- ВЛК офіційно не проходив
- Відсутність розвитку, справедливості та підтримки
- Виснаження моральне й фізичне
- Намір не підписувати контракт

---

## 3. Суть рішення
Я не ухиляюсь від обов’язку перед державою,  
але не погоджуюсь бути частиною системи, що нищить людину замість зміцнювати її.

---

## 4. Право на перехід
> “Людина має невід’ємне право на збереження своєї свідомості, цілісності та гідності.”

Конституційне право на свободу совісті, самозбереження та відновлення.  
Я заявляю про **мирний вихід** із конкретної частини та перехід у **нову форму служіння народу**.

---

## 5. Нова форма служіння
- Інформаційна оборона  
- Аналітика і стратегічна робота  
- Освітні ініціативи DAO-GOGS  
- Підтримка побратимів та громади

---

## 6. Принцип дії

---

## 7. Місія
> “Бути мостом між фронтом і свідомим суспільством.”

Мета — служити Україні розумом, системою і духом.

---

## 8. Символ і Кодекс
🜂 — Полум’я свідомості  
**Кодекс:**  
- Цілісність понад страх  
- Свідомість понад наказ  
- Воля понад форму

---

## 9. Підпис
**Автор:** С.Ч.  
**Місце:** Сказинці, Вінницька обл.  
**Дата:** $day  
**Статус:** Активний документ CHECHA_CORE (C06_FOCUS / EXIT_PATH)

---

© CHECHA_CORE | DAO-GOGS | Громада Свідомих
"@
