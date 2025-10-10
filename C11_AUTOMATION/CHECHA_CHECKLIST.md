\# ✅ CHECHA CHECKLIST — BTD 1.0 (Щотижнева перевірка)



\*\*Періодичність:\*\* щонеділі після формування дайджесту.  

\*\*Відповідальний:\*\* С.Ч.  



---



\## 🔹 Кроки перевірки



1\. \*\*MANIFEST.md\*\*

&nbsp;  - \[ ] Відкрий `C11/MANIFEST.md`  

&nbsp;  - \[ ] Переконайся, що всі файли мають SHA256 (не `—`)  

&nbsp;  - \[ ] Статуси відображають реальний стан (`OK / Draft / Error / Planned`)



2\. \*\*CHECKSUMS.txt\*\*

&nbsp;  - \[ ] Відкрий `C11/CHECKSUMS.txt`  

&nbsp;  - \[ ] Зістав SHA256 з MANIFEST — значення мають збігатися  

&nbsp;  - \[ ] Відсутні записи = 🚨 сигнал



3\. \*\*BTD\_Manifest.json\*\*

&nbsp;  - \[ ] Відкрий `C11/BTD\_Manifest.json`  

&nbsp;  - \[ ] Перевір цілісність JSON (жодних “null” для важливих файлів)



4\. \*\*C03\_LOG\*\*

&nbsp;  - \[ ] Переглянь `C03\_LOG/BTD-Manifest-Commits.log`  

&nbsp;  - \[ ] Останній коміт відображає актуальний SHA MANIFEST  

&nbsp;  - \[ ] Немає записів із `(missing)`



5\. \*\*REPORTS\*\*

&nbsp;  - \[ ] Відкрий останній `REPORTS/BTD\_Manifest\_Digest\_YYYY-MM-DD\_to\_YYYY-MM-DD.md`  

&nbsp;  - \[ ] Таблиця містить записи за тиждень  

&nbsp;  - \[ ] Кількість проблем = 0 (якщо >0 → занотуй і виправи)



6\. \*\*Git / Push\*\*

&nbsp;  - \[ ] Виконай `git status` — репозиторій чистий  

&nbsp;  - \[ ] Виконай `git log -1` — останній коміт має опис `reports: weekly BTD Manifest digest (auto)` або ручний актуальний



7\. \*\*GitHub Actions\*\*

&nbsp;  - \[ ] Перевір у вкладці Actions останній workflow `BTD Weekly Digest`  

&nbsp;  - \[ ] Статус = ✅ Success  

&nbsp;  - \[ ] Artifact `btd-weekly-digest` доступний



---



\## 🔹 Якщо знайдені проблеми

\- \*\*Missing file:\*\* створити/відновити файл → перезапустити `Build-BTD-Manifest.ps1`.  

\- \*\*SHA mismatch:\*\* перевірити файл (можливо змінений вручну) → оновити MANIFEST.  

\- \*\*Bad status:\*\* відкоригувати вручну у MANIFEST.  

\- \*\*Digest errors:\*\* прогнати `Build-WeeklyBTD-Digest.ps1` ще раз.



---



✍ Автор: С.Ч.  



