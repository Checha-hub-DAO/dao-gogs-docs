# 🧩 Build-CadreEvalPackage.ps1
### Автоматичний білдер пакету оцінки кадрів (v1.0)
🟢 **STATUS:** OK · ZIP · Hash=MATCH · GPG=SKIPPED

**Мета:** Створення перевірених релізів (ZIP або теки) з контрольними сумами, manifest.json, опційним підписом GPG та публікацією в Git.

---

## ⚙️ Основні можливості
- Архівація або викладка в теку (-NoZip), збереження структури (-PreserveTree).
- Контрольні суми: SHA512; опційно checksums.txt.
- manifest.json: 	otalFiles/totalBytes + SHA кожного файлу.
- Git-інтеграція: -GitAddCommit, -GitPush.

## 🚀 Типовий запуск
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File "D:\\CHECHA_CORE\\TOOLS\\Build-CadreEvalPackage.ps1" `
  -Version v1.0 `
  -SourceDir "D:\CHECHA_CORE\C12_KNOWLEDGE\MD_AUDIT" `
  -Include ''*.md','*.pdf'' `
  -OutDir "D:\CHECHA_CORE\C03_LOG\reports" `
  -PreserveTree -Force `
  -ChecksumsList:True -HashAlgo SHA512 `
  -GitAddCommit "cadre: package v1.0" -GitPush
```

## 🔍 Вихідні артефакти
- Тип релізу: **ZIP**
 - ZIP: **CadreEval_Package_v1.0_20251016_122153.zip**
 - Шлях: `D:\CHECHA_CORE\C03_LOG\reports\CadreEval_Package_v1.0_20251016_122153.zip`
 - Файлів у пакеті: **26**
 - Сумарний розмір: **9,55 KiB**
 - GPG Verify: **SKIPPED** (нема zip.asc)
 - Hash Verify (CadreEval_Package_v1.0_20251016_122153.zip.sha256.txt): **MATCH**

---

_Оновлено: 2025-10-16 · С.Ч. / DAO-GOGS_
