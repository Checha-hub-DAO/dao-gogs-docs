---

title: MANIFEST — BTD 1.0

description: Маніфест бібліотеки технічних документів CHECHA\_CORE (BTD 1.0).

version: 1.0.0

last\_update: 2025-10-07

author: С.Ч.

---



\# 📜 MANIFEST — BTD 1.0



Цей маніфест фіксує склад, контроль та статус бібліотеки технічних документів (BTD 1.0) у системі \*\*CHECHA\_CORE\*\*.  

Він використовується у \*\*SKD-GOGS\*\* для перевірки цілісності, відтворюваності та актуальності.



---



\## 🔹 Основні відомості

\- \*\*Назва:\*\* BTD 1.0 — Бібліотека технічних документів  

\- \*\*Версія:\*\* v1.0.0  

\- \*\*Дата оновлення:\*\* 2025-10-07  

\- \*\*Відповідальний:\*\* С.Ч.  



---



\## 🔹 Складові (ключові файли)

| Код | Назва                     | Шлях                                           | SHA256 (приклад)                                | Статус |

|-----|---------------------------|-----------------------------------------------|------------------------------------------------|--------|

| BTD-01 | README.md                | C11/README.md                                 | `d41d8cd98f00b204e9800998ecf8427e`             | OK     |

| BTD-02 | TOOLS\_INDEX.md           | C11/tools/INDEX/TOOLS\_INDEX.md                | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b` | OK     |

| BTD-03 | TOOLS\_MAP.csv            | C11/tools/INDEX/TOOLS\_MAP.csv                 | `3a7bd3e2360a3d80f3b9eec7f88f1f54ed5e09d1c7ff` | OK     |

| BTD-04 | MAT\_RESTORE.md           | C07\_ANALYTICS/MAT\_RESTORE.md                  | `19f3a1a0be4f7ddc92a69c4035ad5124ec3e67ba1a8f` | OK     |

| BTD-05 | ITETA\_Dashboard.xlsx     | C07\_ANALYTICS/ITETA\_Dashboard.xlsx            | `f72d2c2be478fc2c55caa1ef9232d9f4aab33f9a22c7` | OK     |

| BTD-06 | Audit-Publish.ps1        | C12\_KNOWLEDGE/MD\_AUDIT/Audit-Publish.ps1      | `bd2e1c52a08cf942bcdef0d109adc9f4a1a64b4475c6` | WARN   |

| BTD-07 | Git\_Control.md           | C12\_KNOWLEDGE/MD\_AUDIT/Git\_Control.md         | `70e9fbb82b63d1b7a8e4cf9e6d83f3c967c9f13b5d17` | ⚠ Draft |

| BTD-08 | INBOX-PerfTrim.ps1       | INBOX/INBOX-PerfTrim.ps1                      | `ad9c28c56f9f2394f345b84a62efc80b7d021f1d92f1` | OK     |

| BTD-09 | SKD-Report.md            | SKD/SKD-Report.md                             | `88a1d7a823ff23a22c23f22f761902dbc5f93724a6f1` | ⚠ Draft |

| BTD-10 | EXPORTS\_GUIDE.md         | EXPORTS/EXPORTS\_GUIDE.md                      | `d88c5b4e789db0a54d46d1521c1a6f3e2b8429af72ef` | ⚠ Planned |



---



\## 🔹 Примітки

\- Значення \*\*SHA256\*\* наведені як приклади, підлягають автооновленню через скрипти.  

\- Поля `Status` можуть мати значення:  

&nbsp; - ✅ \*\*OK\*\* — файл підтверджений і актуальний  

&nbsp; - ⚠ \*\*Draft\*\* — чорновик, потребує наповнення  

&nbsp; - ❌ \*\*Error\*\* — критична помилка, треба виправити  

&nbsp; - ⚠ \*\*Planned\*\* — файл запланований, але ще не створений  



---



✍ Автор: С.Ч.  



