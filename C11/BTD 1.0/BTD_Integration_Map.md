\# 🌐 BTD 1.0 — Інтеграційна карта



```mermaid

flowchart TD



&nbsp; %% Основні вузли

&nbsp; C11\[📘 C11 — BTD 1.0<br/>MANIFEST / CHECKSUMS / INDEX]

&nbsp; C12\[📚 C12\_KNOWLEDGE<br/>MD\_INBOX / MD\_AUDIT / MD\_ARCHIVE]

&nbsp; C03\[📑 C03\_LOG<br/>Журнал змін / AUDIT-логи]

&nbsp; RPT\[📝 REPORTS<br/>Дайджести / Чеклісти / Тести]

&nbsp; TOOLS\[⚙️ TOOLS<br/>Скрипти автоматизації]

&nbsp; INBOX\[📥 INBOX<br/>Вхідний буфер / Артефакти]



&nbsp; %% Взаємозв’язки

&nbsp; INBOX --> C12

&nbsp; C12 --> C11

&nbsp; C11 --> RPT

&nbsp; C11 --> C03

&nbsp; TOOLS --> C11

&nbsp; TOOLS --> RPT

&nbsp; TOOLS --> INBOX

&nbsp; TOOLS --> C03



&nbsp; %% CI/CD та Автоматизація

&nbsp; subgraph AUTO\[🔄 Автоматизація]

&nbsp;   GH\[GitHub Actions<br/>btd-weekly-digest.yml]

&nbsp;   TS\[Windows Task Scheduler]

&nbsp;   HOOKS\[Git Hooks<br/>pre-commit / post-commit]

&nbsp; end



&nbsp; HOOKS --> C11

&nbsp; TS --> TOOLS

&nbsp; GH --> TOOLS



&nbsp; %% Зворотні зв’язки

&nbsp; RPT --> C03

&nbsp; C03 --> C11

&nbsp; C12 --> RPT



&nbsp; %% Стиль

&nbsp; classDef module fill:#1d3557,stroke:#fff,stroke-width:1px,color:#f1faee;

&nbsp; classDef buffer fill:#457b9d,stroke:#fff,stroke-width:1px,color:#f1faee;

&nbsp; classDef reports fill:#e63946,stroke:#fff,stroke-width:1px,color:#fff;

&nbsp; classDef tools fill:#2a9d8f,stroke:#fff,stroke-width:1px,color:#fff;

&nbsp; classDef auto fill:#f4a261,stroke:#fff,stroke-width:1px,color:#fff;



&nbsp; class C11,C12,C03 module

&nbsp; class INBOX buffer

&nbsp; class RPT reports

&nbsp; class TOOLS tools

&nbsp; class GH,TS,HOOKS auto



