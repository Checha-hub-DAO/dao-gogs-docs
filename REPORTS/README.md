\# 📝 REPORTS — Звіти CHECHA\_CORE



Папка \*\*REPORTS\*\* є центральним сховищем згенерованих звітів у системі \*\*CHECHA\_CORE\*\*.  

Тут зберігаються як автоматично сформовані документи (дайджести, тести), так і ручні файли (чеклісти).



---



\## 🔹 Основні типи звітів



\### 1. Щотижневі дайджести BTD

\- Формат: `BTD\_Manifest\_Digest\_YYYY-MM-DD\_to\_YYYY-MM-DD.md`

\- Генерується скриптом `Build-WeeklyBTD-Digest.ps1` (локально і через GitHub Actions)

\- Призначення: підсумковий огляд стану \*\*MANIFEST\*\*, \*\*CHECKSUMS\*\*, файлів C11

\- Індекс: \[BTD\_Manifest\_Digest\_index.md](./BTD\_Manifest\_Digest\_index.md)



\### 2. Щотижневі чеклісти

\- Формат: `CHECHA\_CHECKLIST\_YYYY-MM-DD\_to\_YYYY-MM-DD.md`

\- Створюється скриптом `New-WeeklyChecklist.ps1`

\- Призначення: ручний аудит структури і процесів

\- Індекс: \[CHECHA\_CHECKLIST\_index.md](./CHECHA\_CHECKLIST\_index.md)



\### 3. Тести структури

\- Формат: `BTD\_Structure\_Test\_\*.md`

\- Формується `Test-BTD-Structure.ps1`

\- Призначення: валідація MANIFEST, наявності файлів, статусів



\### 4. Інші звіти

\- Можуть включати додаткові логи, статистику або спеціальні дайджести

\- Використовуються для розширених модулів (наприклад, ITETA, SKD)



---



\## 🔹 Службові файли



\- \*\*CHECKSUMS.txt\*\*  

&nbsp; Актуальні SHA256 для всіх звітів у цій папці.  

&nbsp; Оновлюється автоматично разом з формуванням дайджестів та чеклістів.



---



\## 🔹 Автоматизація



1\. \*\*Локально (Task Scheduler):\*\*

&nbsp;  - щонеділі формується Digest і Checklist

&nbsp;  - о 20:10 → Digest  

&nbsp;  - о 20:15 → Checklist  

&nbsp;  - о 20:20 → Indexes



2\. \*\*GitHub Actions:\*\*

&nbsp;  - workflow `btd-weekly-digest.yml`

&nbsp;  - формує Digest

&nbsp;  - запускає `Update-ReportsIndexes.ps1`

&nbsp;  - комітить оновлені індекси у цю папку



---



\## 🔹 Навігація



\- \[📆 Щотижневі дайджести BTD](./BTD\_Manifest\_Digest\_index.md)  

\- \[✅ Щотижневі чеклісти](./CHECHA\_CHECKLIST\_index.md)



---



✍ Автор: С.Ч.



