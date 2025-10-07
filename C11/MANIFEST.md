---
title: MANIFEST — BTD 1.0
description: Маніфест бібліотеки технічних документів CHECHA_CORE (BTD 1.0).
version: 1.0.0
last_update: 2025-10-07
author: С.Ч.
---

# 📜 MANIFEST — BTD 1.0

Цей маніфест фіксує склад, контроль та статус бібліотеки технічних документів (BTD 1.0) у системі **CHECHA_CORE**.  
Він використовується у **SKD-GOGS** для перевірки цілісності, відтворюваності та актуальності.

---

## 🔹 Основні відомості
- **Назва:** BTD 1.0 — Бібліотека технічних документів  
- **Версія:** v1.0.0  
- **Дата оновлення:** 2025-10-07  
- **Відповідальний:** С.Ч.  

---

## 🔹 Складові (ключові файли)
| Код | Назва                     | Шлях                                           | SHA256 | Статус |
|-----|---------------------------|-----------------------------------------------|--------|--------|
| BTD-01 | README.md                | C11/README.md                                 | — | Draft |
| BTD-02 | TOOLS_INDEX.md           | C11/tools/INDEX/TOOLS_INDEX.md                | — | Draft |
| BTD-03 | TOOLS_MAP.csv            | C11/tools/INDEX/TOOLS_MAP.csv                 | — | Draft |
| BTD-04 | MAT_RESTORE.md           | C07_ANALYTICS/MAT_RESTORE.md                  | — | Draft |
| BTD-05 | ITETA_Dashboard.xlsx     | C07_ANALYTICS/ITETA_Dashboard.xlsx            | — | Draft |
| BTD-06 | Audit-Publish.ps1        | C12_KNOWLEDGE/MD_AUDIT/Audit-Publish.ps1      | — | Draft |
| BTD-07 | Git_Control.md           | C12_KNOWLEDGE/MD_AUDIT/Git_Control.md         | — | Draft |
| BTD-08 | INBOX-PerfTrim.ps1       | INBOX/INBOX-PerfTrim.ps1                      | — | Draft |
| BTD-09 | SKD-Report.md            | SKD/SKD-Report.md                             | — | Draft |
| BTD-10 | EXPORTS_GUIDE.md         | EXPORTS/EXPORTS_GUIDE.md                      | — | Planned |

---

## 🔹 Примітки
- Поля **SHA256** будуть оновлені автоматично за допомогою скрипта `Build-BTD-Manifest.ps1`.  
- **Status** може мати значення:  
  - ✅ OK — файл підтверджений і актуальний  
  - ⚠ Draft — чорновик, потребує наповнення  
  - ❌ Error — критична помилка, файл відсутній або зіпсований  
  - ⏳ Planned — файл запланований, але ще не створений  

---

✍ Автор: С.Ч.  
