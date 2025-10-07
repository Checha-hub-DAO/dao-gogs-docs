---
title: Каталог технічних інструментів
description: Централізований огляд усіх скриптів і технічних засобів CHECHA_CORE. Частина BTD 1.0.
---

# 📖 Каталог технічних інструментів CHECHA_CORE

Цей документ описує ключові інструменти системи **CHECHA_CORE**.  
Він синхронізується з `TOOLS_MAP.csv` (де зберігаються SHA256, статуси та нотатки).  
Мета — забезпечити ефективний контроль, навігацію і прозорість.

---

## 🔹 Автоматизація
- **Run-WeeklyChecklist.ps1**  
  📂 `D:\CHECHA_CORE\TOOLS\Run-WeeklyChecklist.ps1`  
  ✅ Генерує щотижневий чекліст і оновлює CHECKSUMS.

- **Generate-WeeklyChecklistReport.ps1**  
  📂 `D:\CHECHA_CORE\TOOLS\Generate-WeeklyChecklistReport.ps1`  
  ⚠ ParserError (рядок ~18) — пропущена дужка. Потребує виправлення.

- **INBOX-PerfTrim.ps1**  
  📂 `D:\CHECHA_CORE\INBOX\INBOX-PerfTrim.ps1`  
  ✅ Автоматичне скорочення логів/CSV. Працює через планувальник.

- **Run-NewLoveWeekBlock.ps1**  
  📂 `D:\CHECHA_CORE\TOOLS\Run-NewLoveWeekBlock.ps1`  
  ⚠ Помилка Null-об’єкта. Потребує налагодження.

---

## 🔹 Аналітика
- **ITETA_Dashboard (xlsx/csv/html)**  
  📂 `D:\CHECHA_CORE\ITETA\reports\`  
  ✅ Панель еволюційних трендів (Всесвіт / Людина / ШІ).

- **MAT_RESTORE.csv + MD**  
  📂 `D:\CHECHA_CORE\C07_ANALYTICS\`  
  ✅ Матриця Відновлення. Використовується для RestoreTop3.

---

## 🔹 Git / Versioning
- **Audit-Publish.ps1**  
  📂 `D:\CHECHA_CORE\C12_KNOWLEDGE\MD_AUDIT\Audit-Publish.ps1`  
  ⚠ Git remote error — invalid repository name. Перевірити `origin`.

- **Verify-And-Sync-G45.1.ps1**  
  📂 `D:\CHECHA_CORE\TOOLS\Verify-And-Sync-G45.1.ps1`  
  ✅ Перевірка/синхронізація артефактів G45.*

- **Manage_Shield4_Release.ps1**  
  📂 `D:\CHECHA_CORE\TOOLS\Manage_Shield4_Release.ps1`  
  ✅ Пакування релізів модуля “Щит”.

---

## 🔹 Архівування
- **INBOX-Run.ps1**  
  📂 `D:\CHECHA_CORE\INBOX\INBOX-Run.ps1`  
  ✅ Збір і пакування INBOX-артефактів.

- **CheCha-BuildAndArchive (ScheduledTask)**  
  📂 Task Scheduler  
  ⚠ `Access is denied` при запуску без прав адміністратора.

---

## 🔹 Системні
- **MorningPanel-RestoreTop3**  
  📂 Планувальник завдань  
  ✅ Щоденний ранковий запуск Restore Matrix.

- **Evening-RestoreLog**  
  📂 Планувальник завдань  
  ✅ Вечірній запис у FOCUS_RestoreLog.md.

---

## 📌 Нотатки
- Оновлення каталогу:  
  ```powershell
  pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\CHECHA_CORE\TOOLS\Generate-ToolsIndex.ps1" -PreserveNotes
