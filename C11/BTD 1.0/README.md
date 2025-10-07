---

title: BTD 1.0 — Бібліотека технічних документів

description: Центральний каталог технічних артефактів, інструментів та процесів системи CHECHA\_CORE.

---



\# 📖 BTD 1.0 — Бібліотека технічних документів



BTD 1.0 — це \*\*бібліотека технічних документів\*\* системи \*\*CHECHA\_CORE\*\*.  

Вона об’єднує каталоги інструментів, аналітики, аудитів, INBOX, SKD, звітів та експортів.  

Мета — забезпечити \*\*прозорість, контроль і відтворюваність\*\* усіх робочих процесів.



---



\## 🔹 Складові BTD 1.0

\- 📊 \*\*C07 — Аналітика\*\*: RestoreMatrix, ITETA, KROSS / GOES.  

\- 🛠 \*\*C11 — Технічні інструменти\*\*: TOOLS\_INDEX, TOOLS\_MAP, ScheduledTasks.  

\- 📑 \*\*C12 — Аудит і Git\*\*: Audit-Publish, контроль remote/origin, MD\_AUDIT.  

\- 📦 \*\*INBOX\*\*: Run, PerfTrim, SelfCheck, Guide.  

\- 🛡 \*\*SKD-GOGS\*\*: контроль документів і відповідності.  

\- 📝 \*\*REPORTS\*\*: WeeklyChecklist, архіви, гайди по читанню звітів.  

\- 📤 \*\*EXPORTS\*\*: правила експортів і приклади ZIP.  



---



\## 🔹 Візуальна карта (Flowchart)



```mermaid

flowchart TD



&nbsp;   BTD\["📖 BTD 1.0 — Бібліотека технічних документів"]



&nbsp;   subgraph C07\["📊 C07 — Аналітика"]

&nbsp;       R1\["MAT\_RESTORE.md"]

&nbsp;       R2\["ITETA\_Dashboard"]

&nbsp;       R3\["KROSS / GOES"]

&nbsp;   end



&nbsp;   subgraph C11\["🛠 C11 — Технічні інструменти"]

&nbsp;       T1\["TOOLS\_INDEX.md"]

&nbsp;       T2\["TOOLS\_MAP.csv"]

&nbsp;       T3\["ScheduledTasks"]

&nbsp;   end



&nbsp;   subgraph C12\["📑 C12 — Аудит і Git"]

&nbsp;       A1\["Audit-Publish.ps1"]

&nbsp;       A2\["Git\_Control.md"]

&nbsp;       A3\["MD\_AUDIT"]

&nbsp;   end



&nbsp;   subgraph INBOX\["📦 INBOX — Поточні артефакти"]

&nbsp;       I1\["INBOX-Run.ps1"]

&nbsp;       I2\["INBOX-PerfTrim.ps1"]

&nbsp;       I3\["INBOX-SELFCHECK.md"]

&nbsp;       I4\["INBOX\_GUIDE.md"]

&nbsp;   end



&nbsp;   subgraph SKD\["🛡 SKD-GOGS — Контроль документів"]

&nbsp;       S1\["SKD-Report.md"]

&nbsp;       S2\["SKD\_GUIDE.md"]

&nbsp;   end



&nbsp;   subgraph REPORTS\["📝 REPORTS — Звіти"]

&nbsp;       P1\["WeeklyChecklist.md"]

&nbsp;       P2\["ARCHIVE/2025/..."]

&nbsp;       P3\["Гайд: Як читати звіт"]

&nbsp;   end



&nbsp;   subgraph EXPORTS\["📤 EXPORTS — Експорти"]

&nbsp;       E1\["EXPORTS\_GUIDE.md"]

&nbsp;       E2\["ZIP-приклади"]

&nbsp;   end



&nbsp;   BTD --> C07

&nbsp;   BTD --> C11

&nbsp;   BTD --> C12

&nbsp;   BTD --> INBOX

&nbsp;   BTD --> SKD

&nbsp;   BTD --> REPORTS

&nbsp;   BTD --> EXPORTS



