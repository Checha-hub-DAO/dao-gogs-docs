# C11_AUTOMATION — README



> Операційний контур для тижневих перевірок, збірок і дайджестів у **CHECHA CORE**.



---
## 0) Огляд



**C11_AUTOMATION** — набір скриптів PowerShell (pwsh 7+) для:



\* збирання релізів **SHIELD4 ODESA** (Fallback-білдер),

\* інтеграції DAO-модулів (наразі приклад **G43**),

\* тижневого оркестрування кроків (**Weekly**),

\* верифікації модулів з вивантаженням **CSV**,

\* автогенерації **G35 Weekly Digest**,

\* лінтингу here-strings у `.ps1`.



Стандартний корінь: `D:\\CHECHA_CORE`



---
## 1) Передумови



\* Windows, **PowerShell 7+** (`pwsh`)

\* Політика виконання, що дозволяє запуск локальних скриптів:



&nbsp; ```powershell

&nbsp; pwsh -NoProfile -ExecutionPolicy Bypass -File <script>

&nbsp; ```

\* Структура директорій:



&nbsp; \* `C11\\C11_AUTOMATION\\tools` — утиліти (майстер, раннери, лінт)

&nbsp; \* `C11\\C11_AUTOMATION\\steps` — кроки оркестрації (Weekly)

&nbsp; \* `C11\\tools` — інструменти збірки/інтеграції

&nbsp; \* `C11\\SHIELD4_ODESA` — артефакти релізів

&nbsp; \* `C12\\Vault\\DAO` — ZIP-и DAO модулів

&nbsp; \* Логи/звітність: `C03\\LOG\\weekly_reports`



---
## 2) Швидкий старт
### 2.1 Майстер-скрипт



`C11\\C11_AUTOMATION\\tools\\CHECHA-Weekly.ps1` — зводить весь цикл.



**Повний цикл (release → integrate G43 → weekly → verify → digest):**



```powershell

pwsh -NoProfile -ExecutionPolicy Bypass `

&nbsp; -File "D:\\CHECHA_CORE\\C11\\C11_AUTOMATION\\tools\\CHECHA-Weekly.ps1" `

&nbsp; -Root "D:\\CHECHA_CORE" -All `

&nbsp; -Version 'v2.6' `

&nbsp; -NewReleasePath 'C:\\Users\\serge\\Downloads\\SHIELD4_ODESA_UltimatePack_v2.6.zip' `

&nbsp; -ModulesToAdd 'C:\\Users\\serge\\Downloads\\SHIELD4_ODESA_MegaPack_v1.0.zip','C:\\Users\\serge\\Downloads\\SHIELD4_ODESA_MegaVisualPack_v1.0.zip' `

&nbsp; -OpenDigest

```



> Порада: якщо випадково передали файл у `-Root`, скрипт сам візьме його директорію.



**Dry-run (без змін):**



```powershell

pwsh -NoProfile -ExecutionPolicy Bypass `

&nbsp; -File "D:\\CHECHA_CORE\\C11\\C11_AUTOMATION\\tools\\CHECHA-Weekly.ps1" `

&nbsp; -All -Version 'v2.6' -NewReleasePath 'C:\\tmp\\dummy.zip' -DryRun

```



**Локації виводу:**



\* Майстер-лог: `C03\\LOG\\weekly_reports\\CHECHA_Weekly_<timestamp>.log`

\* CSV перевірок: `C03\\LOG\\weekly_reports\\verify_weekly_\*.csv`

\* Weekly-run лог: `C03\\LOG\\weekly_reports\\weekly_\*.run.log`

\* Дайджест: `C03\\LOG\\weekly_reports\\G35_Weekly_Digest_\*.md`



---
## 3) Оркестратор Weekly і кроки



`C11\\C11_AUTOMATION\\tools\\Checha-Orchestrator.ps1` виконує кроки режиму **Weekly**.



**Типові кроки:**



\* `Start-Planning.ps1` — підготовка/планування (stub → швидкий ОК)

\* `Validate-Releases.ps1` — перевірки релізів/DAO (може викликати health-check-и)

\* (опційно) `Lint-Scripts.ps1` — лінт here-strings (див. розділ 7)



> Нові кроки додаємо у `C11\\C11_AUTOMATION\\steps`. Формат: скрипт приймає `-Root`, завершує `exit 0/1`.



**Запуск напряму:**



```powershell

pwsh -NoProfile -ExecutionPolicy Bypass `

&nbsp; -File "D:\\CHECHA_CORE\\C11\\C11_AUTOMATION\\tools\\Checha-Orchestrator.ps1" `

&nbsp; -Mode Weekly -Root "D:\\CHECHA_CORE" -Verbose

```



---
## 4) Верифікація модулів і CSV



`C11\\C11_AUTOMATION\\tools\\Run-DAOModule-VerifyWeekly.ps1`



**Приклад:**



```powershell

\& 'D:\\CHECHA_CORE\\C11\\C11_AUTOMATION\\tools\\Run-DAOModule-VerifyWeekly.ps1' `

&nbsp; -Root 'D:\\CHECHA_CORE' -Modules @('G35','G37','G43') -Csv

```



**Вивід:** таблиця в консолі + `verify_weekly_<timestamp>.csv` у `C03\\LOG\\weekly_reports`.



**Коди/статуси:**



\* `0 → OK`,

\* `64 → SKIP` (напр., «No steps resolved» або кроки-stub),

\* інше → `FAIL`.



---
## 5) Збірка релізів
### 5.1 Fallback-білдер (надійний)



`C11\\tools\\Build_Shield4_Release_Fallback.ps1`



```powershell

\& 'D:\\CHECHA_CORE\\C11\\tools\\Build_Shield4_Release_Fallback.ps1' `

&nbsp; -BaseDir 'D:\\CHECHA_CORE\\C11\\SHIELD4_ODESA' `

&nbsp; -NewReleasePath 'C:\\Users\\serge\\Downloads\\SHIELD4_ODESA_UltimatePack_v2.6.zip' `

&nbsp; -Version 'v2.6' `

&nbsp; -ModulesToAdd @('C:\\Users\\serge\\Downloads\\SHIELD4_ODESA_MegaPack_v1.0.zip',

&nbsp;                 'C:\\Users\\serge\\Downloads\\SHIELD4_ODESA_MegaVisualPack_v1.0.zip')

```



> Після збірки майстер додає SHA256 у `CHECKSUMS_RELEASES.txt`, оновлює `LATEST.txt`, копіює ZIP у `dist/`.
### 5.2 Manage_Shield4_Release_v2_fixed2.ps1



Використовувати з обережністю (вбудовані «охоронці» \*sanity/dry-run\* можуть переривати виконання). Для екстрених збірок — **Fallback**.



---
## 6) Інтеграція DAO-модулів



`C11\\tools\\Integrate-DAOModule_v1.ps1` (стабільна версія)



```powershell
# Автовибір свіжого G43\*.zip із Vault (або вказати -ZipPath)

pwsh -NoProfile -ExecutionPolicy Bypass `

&nbsp; -File 'D:\\CHECHA_CORE\\C11\\tools\\Integrate-DAOModule_v1.ps1' -Module G43

```



Виводить SHA256, розпаковує в `C12\\Vault\\DAO\\G43`, оновлює `C12\\INDEX.md`, дописує в `C03\\LOG\\LOG.md`.



---
## 7) Лінт here-strings у .ps1



`C11\\C11_AUTOMATION\\tools\\Lint-Scripts.ps1`



**Запуск:**



```powershell

pwsh -NoProfile -ExecutionPolicy Bypass `

&nbsp; -File "D:\\CHECHA_CORE\\C11\\C11_AUTOMATION\\tools\\Lint-Scripts.ps1" `

&nbsp; -Root "D:\\CHECHA_CORE" -FailOnUnbalanced -OpenLog

```



**Як крок Weekly:** створити `C11\\C11_AUTOMATION\\steps\\Lint-Scripts.ps1`:



```powershell

param(\[string]$Root='D:\\CHECHA_CORE')

\& (Join-Path $Root 'C11\\C11_AUTOMATION\\tools\\Lint-Scripts.ps1') -Root $Root -FailOnUnbalanced -Quiet

exit $LASTEXITCODE

```



---
## 8) Дайджест (G35 Weekly Digest)



Майстер оновлює/створює `G35_Weekly_Digest_<timestamp>.md` у `C03\\LOG\\weekly_reports`,



\* рахує період **пн–нд**,

\* будує таблицю статусів з останнього CSV,

\* залишає блоки для метрик і рішень.



> Можна примусово щоразу створювати **новий** файл (не оновлювати попередній) — див. коментар у блоці `UpdateDigest` майстер-скрипта.



---
## 9) Планувальник (щоп’ятниці 18:00)



```powershell

$task = 'CHECHA Weekly'

$cmd  = 'pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\\CHECHA_CORE\\C11\\C11_AUTOMATION\\tools\\CHECHA-Weekly.ps1" -Root "D:\\CHECHA_CORE" -All -Version v2.6 -NewReleasePath "C:\\Users\\serge\\Downloads\\SHIELD4_ODESA_UltimatePack_v2.6.zip" -ModulesToAdd "C:\\Users\\serge\\Downloads\\SHIELD4_ODESA_MegaPack_v1.0.zip","C:\\Users\\serge\\Downloads\\SHIELD4_ODESA_MegaVisualPack_v1.0.zip" -OpenDigest'

SCHTASKS /Create /TN "$task" /SC WEEKLY /D FRI /ST 18:00 /TR "$cmd" /RL HIGHEST /F

```



---
## 10) Типові помилки та рішення



\* **Параметр `-Mode` не приймає `VerifyWeekly`:** використовуйте `Weekly` (або `Daily/Monthly/Rolling/Init/Publish`).

\* **`A parameter cannot be found that matches parameter name 'Module'`:** оркестратор не має `-Module`; модульна фільтрація робиться раннером `Run-DAOModule-VerifyWeekly.ps1`.

\* **`No steps resolved for Mode=Weekly`:** немає кроків або лише stub — статус `SKIP (64)` очікуваний.

\* **`.Count` на одиночному об’єкті:** рахуйте через `Measure-Object`.

\* **`Where-Object { param(...` / optimized var overwrite):** не вставляйте `param` усередину скрипт-блоків фільтра.

\* **`ModulesToAdd` дублюється / позиційний аргумент переписав `-Root`:** передавайте масив як `-ModulesToAdd 'a','b'` **та** явно задавайте `-Root`.

\* **Помилки here-string (`@"`):** використовуйте лінтер (розділ 7), заголовок here-string має бути **лише `@"` на своєму рядку**.

\* **Інтегратор впав із синтаксисом:** замініть на стабільну версію (див. розділ 6).



---
## 11) Конвенції



\* Кодування файлів: **UTF-8**.

\* Вихідні коди: `0=OK`, `64=SKIP`, інші — `FAIL`.

\* Логи: у `C03\\LOG\\weekly_reports`, іменування з timestamp `yyyyMMdd_HHmmss`.

\* Усі шляхи — Windows (`D:\\CHECHA_CORE\\...`).



---
## 12) Додаток: корисні сплати



```powershell
# Приклад splat для майстра

$S = \[ordered]@{

&nbsp; Root           = 'D:\\CHECHA_CORE'

&nbsp; All            = $true

&nbsp; Version        = 'v2.6'

&nbsp; NewReleasePath = 'C:\\Users\\serge\\Downloads\\SHIELD4_ODESA_UltimatePack_v2.6.zip'

&nbsp; ModulesToAdd   = @(

&nbsp;   'C:\\Users\\serge\\Downloads\\SHIELD4_ODESA_MegaPack_v1.0.zip',

&nbsp;   'C:\\Users\\serge\\Downloads\\SHIELD4_ODESA_MegaVisualPack_v1.0.zip'

&nbsp; )

&nbsp; OpenDigest     = $true

}



pwsh -NoProfile -ExecutionPolicy Bypass -File `

&nbsp; 'D:\\CHECHA_CORE\\C11\\C11_AUTOMATION\\tools\\CHECHA-Weekly.ps1' @S

```



---



**Maintainer:** C11 Automation

**Останнє оновлення:** \\$(Get-Date -f 'yyyy-MM-dd HH\\:mm')




