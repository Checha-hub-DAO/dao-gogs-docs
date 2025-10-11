# 🗂️ Архів звітів CheCha System — 2025
**Мета:** централізований реєстр релізів, хешів і версій для контролю цілісності та аудиту.  
**Куратор:** С.Ч.  
**Оновлено:** 2025-10-09 20:25:00  

---

## 📦 Поточний цикл релізів
| № | Дата | Назва пакета | Версія | Хеш SHA-256 | Статус | Примітки |
|---|------|---------------|---------|--------------|---------|-----------|
| 1 | 2025-10-09 | CheCha_Report_2025-10-09_v1.0.zip | v1.0 | *внутрішній пакет, інтеграція з Verify-ReportIntegrity.ps1* | ✅ Stable | Початковий стабільний реліз циклу |
| 2 | 2025-10-09 | CheCha_Report_2025-10-09_v1.0.1.zip | v1.0.1 | 9e7ec34a1e8a7a7a49e4dfd6923b2584b33192725959a309a26ac674e3c4f6fc | ✅ Stable | Додано VERSION.txt із метаданими пакета |

---

## 📊 Підсумок за 2025 рік
- **Релізів:** 2  
- **Стабільних:** 2  
- **Виявлених помилок:** 0  
- **Перевірок хешів:** 100 % пройдено успішно  

---

## 🧭 Інструкція ведення
1. Кожен новий реліз додається як новий рядок із номером і датою.  
2. Хеш SHA-256 береться з `CHECKSUMS.txt` або обчислюється вручну:
   ```powershell
   (Get-FileHash 'CheCha_Report_2025-10-09_v1.0.1.zip' -Algorithm SHA256).Hash
   ```
3. Якщо пакет оновлено без зміни вмісту, додається суфікс `v1.0.x` із позначкою “Internal Fix”.
4. У кінці року формується `ARCHIVE_LOG_2025_FINAL.md` із підписом С.Ч. і копіюється до `C05_ARCHIVE`.

---

**Підпис:**  
С.Ч.  
*CheCha System Reports Integrity Chain 2025*

| 3 | 2025-10-09 | CheCha_Report_2025-10-09_v1.1.zip | v1.1 | 831e7a97c9d2cf65b3a3f22a2c7d5f7bcd064920193bb57e85ba360abccf6c5d | ✅ Stable | Integrity Release (з офіційним PDF) |
| 4 | 2025-10-09 | CheCha_Report_2025-10-09_v1.1.zip | v1.1 | 831e7a97c9d2cf65b3a3f22a2c7d5f7bcd064920193bb57e85ba360abccf6c5d | ✅ Stable | Integrity Release (з офіційним PDF) |
| 2025-10-11 | CheCha_Strategic_2025-10-11.zip | 43289 | $sha |
| 2025-10-11 | CheCha_Strategic_2025-10-11.zip | 43289 | $sha |
| 2025-10-11 | strategic | CheCha_Strategic_2025-10-11.zip | 43289 | $sha |
| 2025-10-11 | digest | CheCha_Digest_2025-10-10.zip | 1811 | $sha |
| 2025-10-11 | digest | CheCha_Digest_2025-10-10.zip | 1811 | $sha |
| 2025-10-11 | digest | CheCha_Digest_2025-10-10.zip | 1811 | $sha |
| 2025-10-11 | digest | CheCha_Digest_2025-10-10.zip | 1811 | $sha |
| 2025-10-11 | strategic | CheCha_Strategic_2025-10-11.zip | 43289 | $sha |
| 2025-10-11 | strategic | CheCha_Strategic_2025-10-11.zip | 43289 | $sha |
| 2025-10-11 | strategic | CheCha_Strategic_2025-10-11.zip | 43289 | $sha |
