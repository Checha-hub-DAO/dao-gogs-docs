## v1.0 (2025-10-16)
- Оновлено README/CHANGELOG після релізу.
- Алгоритм хешів: **SHA512**.
**Артефакт:** CadreEval_Package_v1.0_20251016_122153.zip
**Файлів:** 26, **Розмір:** 9,55 KiB
 - GPG Verify: **SKIPPED** (нема zip.asc)
 - Hash Verify (CadreEval_Package_v1.0_20251016_122153.zip.sha256.txt): **MATCH**
🟢 **STATUS:** OK · ZIP · Hash=MATCH · GPG=SKIPPED
- Примітки: - Сервісне оновлення документів.

## v1.0 (2025-10-16)
- Оновлено README/CHANGELOG після релізу.
- Алгоритм хешів: **SHA512**.
**Артефакт:** CadreEval_Package_v1.0_20251016_115118.zip
**Файлів:** 26, **Розмір:** 9,55 KiB
 - GPG Verify: **SKIPPED** (нема zip.asc)
 - Hash Verify (CadreEval_Package_v1.0_20251016_115118.zip.sha256.txt): **MATCH**
🟢 **STATUS:** OK · ZIP · Hash=MATCH · GPG=SKIPPED
- Примітки: Перехід на SHA512; додано checksums.txt

## v1.0 (2025-10-16)
- Оновлено README/CHANGELOG після релізу.
- Алгоритм хешів: **SHA512**.
**Артефакт:** CadreEval_Package_v1.0_20251016_115118.zip
**Файлів:** 26, **Розмір:** 9,55 KiB
 - GPG Verify: **SKIPPED** (gpg не знайдено: C:\Program Files\Gpg4win\bin\gpg.exe)
 - Hash Verify (CadreEval_Package_v1.0_20251016_115118.zip.sha256.txt): **MATCH**
🟢 **STATUS:** OK · ZIP · Hash=MATCH · GPG=SKIPPED
- Примітки: Перехід на SHA512; додано checksums.txt

## v1.0 (2025-10-16)
- Оновлено README/CHANGELOG після релізу.
- Алгоритм хешів: **SHA512**.
**Артефакт:** CadreEval_Package_v1.0_20251016_115118.zip
**Файлів:** 26, **Розмір:** 9,55 KiB
 - GPG Verify: **SKIPPED** (gpg не знайдено: C:\Program Files (x86)\GnuPG\bin\gpg.exe)
 - Hash Verify (CadreEval_Package_v1.0_20251016_115118.zip.sha256.txt): **MATCH**
🟢 **STATUS:** OK · ZIP · Hash=MATCH · GPG=SKIPPED
- Примітки: Перехід на SHA512; додано checksums.txt

---

## 🧾 **CHANGELOG_CadreEval.md**
*(розмістити: `D:\CHECHA_CORE\C11_AUTOMATION\CHANGELOG_CadreEval.md`)*

```markdown
# 🧾 CHANGELOG — Build-CadreEvalPackage.ps1

## v1.2.5 (2025-10-16)
**Стабільна версія.**
- Додано параметр `-HashAlgo` (SHA256 | SHA512 | SHA1 | MD5).
- Новий режим `-ChecksumsList` — формує `checksums.txt` з усіх компонентів.
- Додано `-SignWithGPG` та `-SignTarget (auto|zip|checksums)`.
- Розширено `.gitignore`-винятки для `.asc`, `.sha512.txt`.
- Попередження про слабкі алгоритми SHA1/MD5.
- Легке логування з таймштампами та кольорами.
- Повна сумісність із Git-публікаціями (`-GitForceAdd`, `-AllowReportsInGitignore`).
- Перевірено: збірка, архівація, SHA-хеш, push до `Checha-hub-DAO/dao-gogs-docs.git`.

---

## v1.2.4 (попередня)
- Оптимізовано пошук файлів із fallback-механізмом.
- Додано `-ExcludePatterns` (регулярні вирази).
- Додано `-GitForceAdd`, `-AllowReportsInGitignore`.
- Додано розширений лог `INFO/WARN/ERROR`.

---

## v1.2.3
- Повна сумісність із Git-репозиторіями та CHECHA_CORE структуруванням.
- Збереження дерева тек при `-PreserveTree`.
- Автоматичне створення README.md та manifest.json.

---

## v1.2.1–v1.2.2
- Виправлено відбір файлів (проблема з `-Include`).
- Додано fallback-фільтрацію по розширеннях.
- Підтримано `.md`/`.pdf` незалежно від глибини вкладення.

---

## v1.0 (2025-10-16)
- Початкова стабільна версія білдера CadreEval Package.
- Створення архіву, SHA-256-хеш, базовий manifest.json.
- Структура звітів: `D:\CHECHA_CORE\C03_LOG\reports`.
