# ✅ CHECHA CHECKLIST — BTD 1.0 (Щотижнева перевірка)
**Період:** 2025-10-13 → 2025-10-19  
**Відповідальний:** С.Ч.  

---

## 🔹 Таблиця перевірки

| № | Крок                     | Дія / Що перевірити | Статус |
|---|--------------------------|---------------------|--------|
| 1 | MANIFEST.md              | SHA256 ≠ —, статуси коректні (OK/Draft/Error/Planned) | ☐ |
| 2 | CHECKSUMS.txt (C11)      | Хеші збігаються з MANIFEST | ☐ |
| 3 | BTD_Manifest.json        | JSON цілісний, немає 
ull | ☐ |
| 4 | C03_LOG                  | Останній коміт зафіксовано, немає (missing) | ☐ |
| 5 | REPORTS                  | Останній Digest існує, проблем = 0 | ☐ |
| 6 | Git локально             | git status чистий, git log -1 актуальний | ☐ |
| 7 | GitHub Actions           | BTD Weekly Digest = ✅ Success, артефакт доступний | ☐ |

---

## 🔹 Якщо є проблеми
- Missing file → створити/відновити → запустити Build-BTD-Manifest.ps1  
- SHA mismatch → перевірити файл, оновити MANIFEST  
- Bad status → відкоригувати вручну  
- Digest errors → прогнати Build-WeeklyBTD-Digest.ps1 повторно

— _С.Ч._
