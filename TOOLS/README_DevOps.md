# 🧭 CHECHA_CORE | DevOps README

**Каталог:** `D:\CHECHA_CORE\TOOLS`  
**Статус:** Stable (v1.0, 2025-10-21)  
**Автор:** CheCha DevOps Layer — С.Ч.

---

## ⚙️ Основні скрипти

| Скрипт | Призначення |
|:--|:--|
| `Build-DAOIndexPackage.vNEXT.ps1` | Генерація поточного пакета DAO-індексу (ZIP + SHA256 + LOG). |
| `Run_WeeklyRelease.ps1` | Планувальник тижневого релізу (SYSTEM runner, викликає vNEXT). |
| `Telegram_AutoCore.ps1` | Відправка системних повідомлень у Telegram (режими: alerts, digest). |
| `Verify-DigestChain.ps1` | Перевірка цілісності та хеш-ланцюга дайджестів. |
| `Fix-ArchiveLog.ps1` | Очищення та оновлення архівного логу. |
| `Build-CheChaDigest.ps1` | Створення щоденного дайджесту (MD + TXT + ZIP + SHA256). |
| `Build-AuditChecklist.ps1` | Створення контрольних списків перевірок. |

---

## 🧾 Формат звіту SUMMARY

Типовий фінал успішного запуску:

```text
=== SUMMARY ===
ZIP: DAO-ARCHITECTURE_v2.0_2025-10-21.zip
SHA256: 2c4699e4e1adce8144a965d73d1426a8c83bc2b52dccec8f8d56499ec905ba52
Runner done.
```

---

## 🗓️ Автоматизація

- **Weekly Release:**  
  Планувальник `CHECHA_DAOIndex_WeeklyRelease` запускає `Run_WeeklyRelease.ps1`  
  під обліковим записом SYSTEM з рівнем HIGHEST.

- **SelfTest:**  
  Завдання `CHECHA_SelfTest_DAOIndex_Weekly` виконує `SelfTest_vNEXT.ps1`  
  для перевірки коректності структури та індекс-пакетів.

---

## 🧰 Використання

1. Запуск вручну:
   ```powershell
   pwsh -NoProfile -File "D:\CHECHA_CORE\TOOLS\Build-DAOIndexPackage.vNEXT.ps1" -UseStaging -JsonSummary -VerboseSummary
   ```
2. Перевірка звіту:
   ```powershell
   Get-Content "D:\CHECHA_CORE\C03_LOG\reports\DAO-ARCHITECTURE_*.log" -Tail 40
   ```
3. Хеш-перевірка:
   ```powershell
   Get-FileHash "README_DevOps_v1.0.zip" -Algorithm SHA256
   ```

---

## ✍️ Підпис

> CheCha DevOps Layer — С.Ч.  
> Автоматизаційне ядро системи **CHECHA_CORE / DAO-GOGS**
