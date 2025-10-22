# DevOps Layer v1.1 — README_DevOps для GitBook

**Дата:** 2025-10-22  
**Тег:** \$TagName\

## 🔍 Highlights
- Оновлений README_DevOps для GitBook (структура, сценарії публікації, перевірки інтегриті).
- MANIFEST з контрольними сумами та розмірами.
- (Опційно) GPG-підпис артефактів для перевірки походження.

## 📦 Артефакти
- \README_DevOps_v1.1_GitBook.zip\
- \MANIFEST_DevOps_v1.1.txt\
- \*.sha256.txt\, \*.sig\, \GPG_RELEASE_PUBKEY_<FPR>.asc\

## ✅ Інтегриті
- \SHA256(README_DevOps_v1.1_GitBook.zip): 56475CB88D86E37840050B9EB1266B934F34833044C8A82E8CE491C90D97DCFE\
- \SHA256(MANIFEST_DevOps_v1.1.txt): 6442E0EB2CDEE93401805213118EE3D36F4806A8BFA21F03226B33D0D968A198\

## 🔏 Перевірка
\\\powershell
Get-FileHash -Algorithm SHA256 .\README_DevOps_v1.1_GitBook.zip
gpg --import .\GPG_RELEASE_PUBKEY_<FPR>.asc
gpg --verify .\README_DevOps_v1.1_GitBook.zip.sig .\README_DevOps_v1.1_GitBook.zip
\\\
