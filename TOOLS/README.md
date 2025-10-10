\# ⚙️ TOOLS — Технічні скрипти CHECHA\_CORE



Ця папка містить утиліти для підтримки бібліотеки технічних документів (\*\*BTD 1.0\*\*) та звітності у системі \*\*CHECHA\_CORE\*\*.



---



\## 🔹 Основні скрипти



\### 1. Build-BTD-Manifest.ps1

\- \*\*Мета:\*\* будує `MANIFEST.md`, `CHECKSUMS.txt` і `BTD\_Manifest.json` для C11.  

\- \*\*Де використовується:\*\* у git pre-commit hook, для контролю цілісності.  

\- \*\*Запуск вручну:\*\*

&nbsp; ```powershell

&nbsp; pwsh -NoProfile -File .\\TOOLS\\Build-BTD-Manifest.ps1



